import Foundation

let usage = """
notchctl, push a notification into the MacInotch notch

USAGE
  notchctl [TITLE] [BODY] [options]

OPTIONS
  -s, --source   claude | chatgpt | spotify | system | custom   (default: custom)
  -t, --title    Title text
  -b, --body     Body text
  -k, --kind     info | success | warning | error | progress | attention | music
  -p, --progress 0.0 to 1.0   (implies --kind progress)
      --key      Stable id; sending the same key updates that item in place
      --timeout  Seconds before it disappears (0 = never)
      --dismiss  Remove the item with this key
      --sound    Play a sound
      --port     Endpoint port (default 9977)
  -h, --help

  fan            Quick fan control:
                   notchctl fan blast          blast for 5 minutes
                   notchctl fan blast 15       blast for 15 minutes
                   notchctl fan 50 10          50% for 10 minutes
                   notchctl fan auto           hand control back to macOS
                   notchctl fan                show current fan state
                 Needs the fan helper installed (Settings -> Fans).

  watch          Pipe a command's output through the notch:
                   make 2>&1 | notchctl watch --key build --title "Building"
                 Each line becomes the item's body; the item clears when the
                 pipe closes. Exit status is reflected as success or error.

EXAMPLES
  notchctl "Build finished" "42 tests passed" -s claude -k success
  notchctl --key deploy --progress 0.6 --title "Deploying"
  notchctl --key deploy --kind attention --title "Approve the release?"
  notchctl --dismiss deploy
  swift build 2>&1 | notchctl watch --title "Compiling" -s claude
"""

var payload: [String: Any] = [:]
var port = 9977
var positional: [String] = []

var args = Array(CommandLine.arguments.dropFirst())

let watchMode = args.first == "watch"
if watchMode { args.removeFirst() }

let fanMode = args.first == "fan"
if fanMode { args.removeFirst() }

var i = 0
func next(_ flag: String) -> String {
    i += 1
    guard i < args.count else {
        FileHandle.standardError.write(Data("notchctl: \(flag) needs a value\n".utf8))
        exit(2)
    }
    return args[i]
}

while i < args.count {
    let a = args[i]
    switch a {
    case "-h", "--help":     print(usage); exit(0)
    case "-s", "--source":   payload["source"] = next(a)
    case "-t", "--title":    payload["title"] = next(a)
    case "-b", "--body":     payload["body"] = next(a)
    case "-k", "--kind":     payload["kind"] = next(a)
    case "--key":            payload["key"] = next(a)
    case "--dismiss":        payload["dismiss"] = next(a)
    case "--sound":          payload["sound"] = true
    case "-p", "--progress":
        payload["progress"] = Double(next(a)) ?? 0
        if payload["kind"] == nil { payload["kind"] = "progress" }
    case "--timeout":
        let v = Double(next(a)) ?? 0
        payload["timeout"] = v == 0 ? Double.greatestFiniteMagnitude : v
    case "--port":           port = Int(next(a)) ?? port
    default:
        if a.hasPrefix("-") {
            FileHandle.standardError.write(Data("notchctl: unknown option \(a)\n".utf8))
            exit(2)
        }
        positional.append(a)
    }
    i += 1
}

if payload["title"] == nil, positional.count > 0 { payload["title"] = positional[0] }
if payload["body"] == nil, positional.count > 1 { payload["body"] = positional[1] }

func request(path: String, body: [String: Any]?, port: Int) -> (Int, String)? {
    guard let url = URL(string: "http://127.0.0.1:\(port)\(path)") else { return nil }
    var req = URLRequest(url: url)
    req.timeoutInterval = 3
    if let body {
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try? JSONSerialization.data(withJSONObject: body)
    }
    var result: (Int, String)?
    let done = DispatchSemaphore(value: 0)
    URLSession.shared.dataTask(with: req) { data, response, _ in
        if let http = response as? HTTPURLResponse {
            result = (http.statusCode, String(decoding: data ?? Data(), as: UTF8.self))
        }
        done.signal()
    }.resume()
    _ = done.wait(timeout: .now() + 4)
    return result
}

if fanMode {
    var body: [String: Any]?
    let first = args.first?.lowercased()

    switch first {
    case nil:
        body = nil
    case "auto", "off", "reset":
        body = ["auto": 1]
    case "blast", "max", "full":
        body = ["percent": 1.0, "minutes": args.count > 1 ? Double(args[1]) ?? 5 : 5]
    default:
        guard let raw = first, let number = Double(raw) else {
            let message = "notchctl: fan needs a percentage, 'blast' or 'auto'\n"
            FileHandle.standardError.write(Data(message.utf8))
            exit(2)
        }
        let percent = number > 1 ? number / 100 : number
        body = ["percent": min(max(percent, 0), 1),
                "minutes": args.count > 1 ? Double(args[1]) ?? 5 : 5]
    }

    guard let (code, text) = request(path: "/fan", body: body, port: port), code == 200 else {
        FileHandle.standardError.write(Data(
            "notchctl: MacInotch is not listening on port \(port)\n".utf8))
        exit(1)
    }

    if let data = text.data(using: .utf8),
       let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
        let helper = obj["helper"] as? String ?? "unknown"
        if helper != "running" {
            print("fan helper: \(helper), install it from Settings > Fans")
        }
        for fan in (obj["fans"] as? [[String: Any]] ?? []) {
            let index = (fan["index"] as? Int ?? 0) + 1
            let rpm = fan["rpm"] as? Int ?? 0
            let hold = fan["holdsFor"] as? Int ?? 0
            let suffix = hold > 0 ? "  holding \(hold / 60)m \(hold % 60)s" : ""
            print("fan \(index): \(rpm == 0 ? "stopped" : "\(rpm) rpm")\(suffix)")
        }
        if let watts = obj["watts"] as? Double, watts > 0 {
            print(String(format: "power: %.1f W", watts))
        }
    }
    exit(0)
}

if payload.isEmpty && !watchMode { print(usage); exit(0) }

if watchMode {
    let key = (payload["key"] as? String) ?? "watch-\(ProcessInfo.processInfo.processIdentifier)"
    let title = (payload["title"] as? String) ?? "Running"
    let source = (payload["source"] as? String) ?? "custom"
    let port = port

    func post(_ body: [String: Any]) {
        guard let data = try? JSONSerialization.data(withJSONObject: body),
              let url = URL(string: "http://127.0.0.1:\(port)/notify") else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = data
        request.timeoutInterval = 2
        let done = DispatchSemaphore(value: 0)
        URLSession.shared.dataTask(with: request) { _, _, _ in done.signal() }.resume()
        _ = done.wait(timeout: .now() + 2)
    }

    post(["key": key, "title": title, "source": source,
          "kind": "progress", "body": "starting…", "timeout": 86400])

    var lastLine = ""
    var sent = Date.distantPast
    while let line = readLine(strippingNewline: true) {

        print(line)
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { continue }
        lastLine = String(trimmed.prefix(90))

        if Date().timeIntervalSince(sent) > 0.4 {
            sent = Date()
            post(["key": key, "title": title, "source": source,
                  "kind": "progress", "body": lastLine, "timeout": 86400])
        }
    }

    post(["key": key, "title": title, "source": source, "kind": "success",
          "body": lastLine.isEmpty ? "done" : lastLine, "timeout": 6])
    exit(0)
}

if let t = payload["timeout"] as? Double, !t.isFinite { payload["timeout"] = 315_360_000.0 }

guard let body = try? JSONSerialization.data(withJSONObject: payload),
      let url = URL(string: "http://127.0.0.1:\(port)/notify") else {
    FileHandle.standardError.write(Data("notchctl: could not build request\n".utf8))
    exit(1)
}

var req = URLRequest(url: url)
req.httpMethod = "POST"
req.setValue("application/json", forHTTPHeaderField: "Content-Type")
req.httpBody = body
req.timeoutInterval = 3

let sem = DispatchSemaphore(value: 0)
var status: Int32 = 1
URLSession.shared.dataTask(with: req) { _, response, error in
    if let error {
        FileHandle.standardError.write(Data(
            "notchctl: MacInotch is not listening on port \(port) (\(error.localizedDescription))\n".utf8))
    } else if let http = response as? HTTPURLResponse, http.statusCode == 200 {
        status = 0
    } else {
        FileHandle.standardError.write(Data("notchctl: rejected by MacInotch\n".utf8))
    }
    sem.signal()
}.resume()
sem.wait()
exit(status)
