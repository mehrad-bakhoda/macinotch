import AppKit
import Foundation

struct MailMessage: Identifiable, Equatable {
    var id: String
    var sender: String
    var senderAddress: String
    var subject: String
    var received: Date
    var flagged: Bool
    var account: String
    var preview: String
    var summary: String = ""
    var triage: MailTriage?
    var listMail: Bool = false

    var important: Bool { flagged || triage == .urgent }
    var wantsAnswer: Bool { triage?.wantsAnswer ?? false }

    var ago: String {
        let seconds = Int(Date().timeIntervalSince(received))
        if seconds < 3600 { return "\(max(1, seconds / 60))m ago" }
        if seconds < 86400 { return "\(seconds / 3600)h ago" }
        return "\(seconds / 86400)d ago"
    }

    var initials: String {
        let parts = sender.split(separator: " ").prefix(2)
        let letters = parts.compactMap { $0.first }.map(String.init)
        return letters.isEmpty ? "?" : letters.joined().uppercased()
    }
}

enum MailState: Equatable {
    case notRunning
    case noAccounts
    case denied
    case ready
}

@MainActor
final class MailService: ObservableObject {
    static let shared = MailService()

    @Published private(set) var messages: [MailMessage] = []
    @Published private(set) var state: MailState = .notRunning
    @Published private(set) var busy = false
    @Published var lastError = ""
    @Published var replyingTo: String?
    @Published var draft = ""
    @Published var sending = false
    @Published var drafting = false

    private var timer: Timer?
    private var announced: Set<String> = []
    private var primed = false

    private init() {}

    func start() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 90, repeats: true) { _ in
            Task { @MainActor in await MailService.shared.refresh() }
        }
        Task { await refresh() }
    }

    func stop() { timer?.invalidate(); timer = nil }

    static var mailIsRunning: Bool {
        NSWorkspace.shared.runningApplications.contains {
            $0.bundleIdentifier == "com.apple.mail"
        }
    }

    func openMail() {
        guard let url = NSWorkspace.shared
            .urlForApplication(withBundleIdentifier: "com.apple.mail") else { return }
        NSWorkspace.shared.openApplication(at: url,
                                           configuration: NSWorkspace.OpenConfiguration())
    }

    func openAccountSettings() {
        if let url = URL(string:
            "x-apple.systempreferences:com.apple.Internet-Accounts-Settings.extension") {
            NSWorkspace.shared.open(url)
        }
    }

    func refresh() async {
        guard Prefs.shared.d.showMail, !busy else { return }
        guard !demoLocked else { return }
        guard Self.mailIsRunning else {
            state = .notRunning
            if !messages.isEmpty { messages = [] }
            return
        }

        busy = true
        defer { busy = false }

        let hours = Prefs.shared.d.mailWindowHours
        let limit = Prefs.shared.d.mailLimit
        let outcome = await Task.detached(priority: .utility) {
            Self.fetch(hours: hours, limit: limit)
        }.value

        switch outcome {
        case .failure(let reason):
            state = reason
            if !messages.isEmpty { messages = [] }
        case .success(var found):
            state = found.isEmpty && Prefs.shared.d.mailHasAccounts == false
                ? .noAccounts : .ready
            Prefs.shared.d.mailHasAccounts = true

            for index in found.indices {
                if let existing = messages.first(where: { $0.id == found[index].id }) {
                    if !existing.summary.isEmpty {
                        found[index].summary = existing.summary
                    }
                    if existing.triage != nil { found[index].triage = existing.triage }
                }
            }
            messages = found
            announce(found)
            await summarise()
        }
    }

    private func announce(_ found: [MailMessage]) {
        defer { primed = true }
        guard Prefs.shared.d.notifyOnMail else { return }

        for message in found where !announced.contains(message.id) {
            announced.insert(message.id)
            guard primed else { continue }

            var p = NotchPayload()
            p.source = NotchSource.system.rawValue
            p.kind = message.important ? "attention" : "info"
            p.key = "mail-\(message.id)"
            p.title = message.sender
            p.body = message.subject
            p.timeout = message.important ? 20 : 10
            p.sound = true
            p.actions = [NotchAction(label: "Read it",
                                     url: "macinotch://tab?name=mail")]
            NotchState.shared.handle(p)
        }
        if announced.count > 400 { announced.removeAll() }
    }

    private func summarise() async {
        guard Prefs.shared.d.mailSummaries else { return }
        let pending = messages.filter {
            ($0.summary.isEmpty || $0.triage == nil) && !$0.preview.isEmpty
        }
        guard !pending.isEmpty else { return }

        for message in pending.prefix(8) {
            let text = message.preview
            let subject = message.subject

            if message.summary.isEmpty {
                let result = await Summarizer.shared.summarise(subject: subject,
                                                               body: text)
                if !result.isEmpty,
                   let index = messages.firstIndex(where: { $0.id == message.id }) {
                    messages[index].summary = result
                }
            }

            if message.triage == nil {
                let verdict = await Summarizer.shared.triage(
                    subject: subject, body: text,
                    sender: message.senderAddress, bulkHint: message.listMail)
                if let index = messages.firstIndex(where: { $0.id == message.id }) {
                    messages[index].triage = verdict
                }
            }
        }
        sortMessages()
    }

    private func sortMessages() {
        guard Prefs.shared.d.mailSortByImportance else { return }
        messages.sort {
            let left = $0.triage?.rank ?? 2
            let right = $1.triage?.rank ?? 2
            if left != right { return left < right }
            return $0.received > $1.received
        }
    }

    func draftReply(for id: String) {
        guard let message = messages.first(where: { $0.id == id }) else { return }
        drafting = true
        let subject = message.subject
        let body = message.preview
        let sender = message.sender

        Task {
            let suggestion = await Summarizer.shared.replyDraft(
                subject: subject, body: body, sender: sender)
            drafting = false
            guard !suggestion.isEmpty else {
                lastError = "No suggestion could be written for that one."
                return
            }
            draft = suggestion
        }
    }

    func beginReply(to id: String) {
        replyingTo = id
        draft = ""
        lastError = ""
    }

    func cancelReply() {
        replyingTo = nil
        draft = ""
    }

    func sendReply() {
        guard let id = replyingTo else { return }
        let body = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !body.isEmpty else { return }

        sending = true
        Task.detached(priority: .userInitiated) {
            let sent = Self.reply(id: id, body: body)
            await MainActor.run {
                let service = MailService.shared
                service.sending = false
                if sent {
                    service.replyingTo = nil
                    service.draft = ""
                    service.lastError = ""
                    Task { await service.refresh() }
                } else {
                    service.lastError = "Mail would not send that reply."
                }
            }
        }
    }

    func markRead(_ id: String) {
        Task.detached(priority: .utility) {
            _ = Self.run(script: """
            tell application "Mail"
                repeat with m in (messages of inbox whose id is \(id))
                    set read status of m to true
                end repeat
            end tell
            """)
            await MainActor.run { Task { await MailService.shared.refresh() } }
        }
    }

    func openInMail(_ id: String) {
        Task.detached(priority: .utility) {
            _ = Self.run(script: """
            tell application "Mail"
                activate
                repeat with m in (messages of inbox whose id is \(id))
                    open m
                end repeat
            end tell
            """)
        }
    }

    private enum Outcome {
        case success([MailMessage])
        case failure(MailState)
    }

    private nonisolated static func fetch(hours: Double, limit: Int) -> Outcome {
        let script = """
        tell application "Mail"
            set cutoff to (current date) - (\(Int(hours * 3600)))
            set out to ""
            set pool to (messages of inbox whose read status is false ¬
                and date received > cutoff)
            set total to count of pool
            if total > \(limit) then set total to \(limit)
            repeat with i from 1 to total
                set m to item i of pool
                set body to ""
                try
                    set body to (content of m)
                end try
                if (length of body) > 1400 then set body to text 1 thru 1400 of body
                set flagState to "0"
                try
                    if flagged status of m then set flagState to "1"
                end try
                set senderName to ""
                try
                    set senderName to (extract name from sender of m)
                end try
                set senderMail to ""
                try
                    set senderMail to (extract address from sender of m)
                end try
                set acct to ""
                try
                    set acct to (name of account of mailbox of m)
                end try
                set bulkFlag to "0"
                try
                    if (content of (header "list-unsubscribe" of m)) is not "" then ¬
                        set bulkFlag to "1"
                end try
                set out to out & (id of m as text) & (ASCII character 31) & ¬
                    senderName & (ASCII character 31) & ¬
                    senderMail & (ASCII character 31) & ¬
                    (subject of m as text) & (ASCII character 31) & ¬
                    ((date received of m) as «class isot» as string) & ¬
                    (ASCII character 31) & flagState & (ASCII character 31) & ¬
                    acct & (ASCII character 31) & body & (ASCII character 31) & ¬
                    bulkFlag & (ASCII character 30)
            end repeat
            return out
        end tell
        """

        guard let raw = run(script: script) else { return .failure(.denied) }
        if raw.isEmpty { return .success([]) }

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"

        var found: [MailMessage] = []
        for record in raw.components(separatedBy: "\u{1E}") where !record.isEmpty {
            let parts = record.components(separatedBy: "\u{1F}")
            guard parts.count >= 8 else { continue }

            let name = parts[1].isEmpty ? parts[2] : parts[1]
            found.append(MailMessage(
                id: parts[0].trimmingCharacters(in: .whitespacesAndNewlines),
                sender: name.isEmpty ? "Unknown" : name,
                senderAddress: parts[2],
                subject: parts[3].isEmpty ? "No subject" : parts[3],
                received: formatter.date(from: parts[4]) ?? Date(),
                flagged: parts[5] == "1",
                account: parts[6],
                preview: Self.clean(parts[7]),
                listMail: parts.count > 8 && parts[8] == "1"))
        }
        return .success(found.sorted { $0.received > $1.received })
    }

    private nonisolated static func reply(id: String, body: String) -> Bool {
        let escaped = body
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        let script = """
        tell application "Mail"
            set target to missing value
            repeat with m in (messages of inbox whose id is \(id))
                set target to m
            end repeat
            if target is missing value then return "no"
            set answer to reply target with opening window
            tell answer
                set content to "\(escaped)" & return & return & (content of answer)
            end tell
            send answer
            return "yes"
        end tell
        """
        return run(script: script)?.hasPrefix("yes") ?? false
    }

    nonisolated static func clean(_ text: String) -> String {
        var lines: [String] = []
        for raw in text.components(separatedBy: .newlines) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix(">") { continue }
            if line.hasPrefix("On ") && line.hasSuffix("wrote:") { break }
            if line == "--" || line.hasPrefix("-- ") { break }
            if line.lowercased().hasPrefix("unsubscribe") { continue }
            lines.append(line)
            if lines.joined(separator: " ").count > 900 { break }
        }
        return lines.joined(separator: " ")
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
    }

    private nonisolated static func run(script: String) -> String? {
        var error: NSDictionary?
        let value = NSAppleScript(source: script)?.executeAndReturnError(&error)
        if error != nil { return nil }
        return value?.stringValue ?? ""
    }

    private var demoLocked = false

    func loadDemo(_ items: [MailMessage]) {
        demoLocked = true
        messages = items
        state = .ready
        stop()
    }

}
