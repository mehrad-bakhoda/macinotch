import Foundation
import Network

final class NotchServer: @unchecked Sendable {
    static let port: UInt16 = 9977

    private var listener: NWListener?
    private let onPayload: @Sendable (NotchPayload) -> Void
    private let stateJSON: @Sendable () -> String
    private let onPrefsPatch: @Sendable (Data) -> Void
    private let onFanCommand: @Sendable ([String: Any]) -> String

    init(onPayload: @escaping @Sendable (NotchPayload) -> Void,
         stateJSON: @escaping @Sendable () -> String = { "{}" },
         onPrefsPatch: @escaping @Sendable (Data) -> Void = { _ in },
         onFanCommand: @escaping @Sendable ([String: Any]) -> String = { _ in "{}" }) {
        self.onPayload = onPayload
        self.stateJSON = stateJSON
        self.onPrefsPatch = onPrefsPatch
        self.onFanCommand = onFanCommand
    }

    func start() {
        let params = NWParameters.tcp
        params.requiredLocalEndpoint = .hostPort(host: .ipv4(.loopback),
                                                 port: .init(rawValue: Self.port)!)
        params.allowLocalEndpointReuse = true
        guard let l = try? NWListener(using: params) else {
            NSLog("[macinotch] could not bind port \(Self.port)")
            return
        }
        l.newConnectionHandler = { [weak self] conn in self?.accept(conn) }
        l.stateUpdateHandler = { st in
            if case .failed(let e) = st { NSLog("[macinotch] listener failed: \(e)") }
        }
        l.start(queue: .global(qos: .utility))
        listener = l
    }

    func stop() { listener?.cancel(); listener = nil }

    private func accept(_ conn: NWConnection) {
        conn.start(queue: .global(qos: .utility))
        receive(conn, buffer: Data())
    }

    private func receive(_ conn: NWConnection, buffer: Data) {
        conn.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) {
            [weak self] chunk, _, done, error in
            guard let self else { return }
            var buf = buffer
            if let chunk { buf.append(chunk) }

            if error != nil { conn.cancel(); return }

            if let request = Self.parse(buf) {
                self.dispatch(request, on: conn)
                return
            }
            if done { conn.cancel(); return }
            if buf.count > 512 * 1024 { conn.cancel(); return }
            self.receive(conn, buffer: buf)
        }
    }

    private struct Request { var method: String; var path: String; var body: Data }

    private static func parse(_ data: Data) -> Request? {
        let sep = Data("\r\n\r\n".utf8)
        guard let r = data.range(of: sep) else { return nil }
        let head = String(decoding: data[..<r.lowerBound], as: UTF8.self)
        let lines = head.components(separatedBy: "\r\n")
        guard let start = lines.first else { return nil }
        let parts = start.split(separator: " ")
        guard parts.count >= 2 else { return nil }

        var length = 0
        for line in lines.dropFirst() where line.lowercased().hasPrefix("content-length:") {
            length = Int(line.dropFirst("content-length:".count)
                .trimmingCharacters(in: .whitespaces)) ?? 0
        }
        let body = data[r.upperBound...]
        guard body.count >= length else { return nil }
        return Request(method: String(parts[0]), path: String(parts[1]),
                       body: Data(body.prefix(length)))
    }

    private func dispatch(_ req: Request, on conn: NWConnection) {
        let path = req.path.components(separatedBy: "?").first ?? req.path

        switch path {
        case "/health":
            respond(conn, 200, #"{"ok":true,"app":"macinotch"}"#)

        case "/state":
            respond(conn, 200, stateJSON())

        case "/fan":
            var command: [String: Any] = [:]
            if !req.body.isEmpty,
               let parsed = try? JSONSerialization.jsonObject(with: req.body)
                   as? [String: Any] {
                command = parsed
            } else if let comps = URLComponents(string: "http://localhost" + req.path) {
                for item in comps.queryItems ?? [] {
                    if let number = item.value.flatMap(Double.init) {
                        command[item.name] = number
                    } else {
                        command[item.name] = item.value ?? ""
                    }
                }
            }
            respond(conn, 200, onFanCommand(command))

        case "/prefs":

            if req.method == "POST", !req.body.isEmpty {
                guard (try? JSONSerialization.jsonObject(with: req.body)) != nil else {
                    respond(conn, 400, #"{"ok":false,"error":"invalid json"}"#); return
                }
                onPrefsPatch(req.body)
                respond(conn, 200, #"{"ok":true}"#)
            } else {
                respond(conn, 200, SnapshotStore.shared.getPrefs())
            }

        case "/notify":
            var payload: NotchPayload?
            if !req.body.isEmpty {
                payload = try? JSONDecoder().decode(NotchPayload.self, from: req.body)
            }
            if payload == nil { payload = Self.payloadFromQuery(req.path) }
            guard let payload else {
                respond(conn, 400, #"{"ok":false,"error":"bad payload"}"#); return
            }
            onPayload(payload)
            respond(conn, 200, #"{"ok":true}"#)

        default:
            respond(conn, 404, #"{"ok":false,"error":"no such route"}"#)
        }
    }

    private static func payloadFromQuery(_ path: String) -> NotchPayload? {
        guard let comps = URLComponents(string: "http://localhost" + path),
              let items = comps.queryItems, !items.isEmpty else { return nil }
        var p = NotchPayload()
        for i in items {
            let v = i.value
            switch i.name {
            case "source":   p.source = v
            case "title":    p.title = v
            case "body":     p.body = v
            case "kind":     p.kind = v
            case "key":      p.key = v
            case "dismiss":  p.dismiss = v
            case "progress": p.progress = v.flatMap(Double.init)
            case "timeout":  p.timeout = v.flatMap(Double.init)
            case "sound":    p.sound = (v == "1" || v == "true")
            default: break
            }
        }
        return p
    }

    private func respond(_ conn: NWConnection, _ code: Int, _ json: String) {
        let body = Data(json.utf8)
        let head = """
        HTTP/1.1 \(code) \(code == 200 ? "OK" : "Error")\r
        Content-Type: application/json\r
        Content-Length: \(body.count)\r
        Connection: close\r
        \r

        """
        var out = Data(head.utf8)
        out.append(body)
        conn.send(content: out, completion: .contentProcessed { _ in conn.cancel() })
    }
}
