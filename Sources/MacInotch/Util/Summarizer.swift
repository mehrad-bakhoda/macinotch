import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

enum MailTriage: String, Codable, Equatable {
    case urgent
    case reply
    case notice
    case bulk

    var label: String {
        switch self {
        case .urgent: return "Needs you now"
        case .reply: return "Wants a reply"
        case .notice: return "For information"
        case .bulk: return "Marketing"
        }
    }

    var short: String {
        switch self {
        case .urgent: return "URGENT"
        case .reply: return "REPLY"
        case .notice: return "FYI"
        case .bulk: return "BULK"
        }
    }

    var rank: Int {
        switch self {
        case .urgent: return 0
        case .reply: return 1
        case .notice: return 2
        case .bulk: return 3
        }
    }

    var wantsAnswer: Bool { self == .urgent || self == .reply }
}

actor Summarizer {
    static let shared = Summarizer()

    private var cache: [String: String] = [:]
    private var triageCache: [String: MailTriage] = [:]

    static var onDeviceAvailable: Bool {
        #if canImport(FoundationModels)
        if #available(macOS 26.0, *) {
            if case .available = SystemLanguageModel.default.availability { return true }
        }
        #endif
        return false
    }

    func summarise(subject: String, body: String) async -> String {
        let key = subject + "\u{1F}" + String(body.prefix(200))
        if let cached = cache[key] { return cached }

        var result = await onDevice(subject: subject, body: body)
        if result.isEmpty { result = Self.extractive(body) }

        cache[key] = result
        if cache.count > 300 { cache.removeAll() }
        return result
    }

    private func onDevice(subject: String, body: String) async -> String {
        #if canImport(FoundationModels)
        if #available(macOS 26.0, *) {
            guard case .available = SystemLanguageModel.default.availability else {
                return ""
            }
            let session = LanguageModelSession(instructions: """
            You summarise an email in one short sentence, at most twenty words. \
            State what it asks for or tells the reader. No greeting, no sign off, \
            no preamble, and never invent detail that is not present.
            """)
            let prompt = "Subject: \(subject)\n\n\(body.prefix(1200))"
            guard let response = try? await session.respond(to: prompt) else { return "" }
            return response.content.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        #endif
        return ""
    }

    func triage(subject: String, body: String, sender: String,
                bulkHint: Bool) async -> MailTriage {
        if bulkHint { return .bulk }

        let key = "t\u{1F}" + subject + String(body.prefix(160))
        if let cached = triageCache[key] { return cached }

        var verdict = Self.heuristic(subject: subject, body: body, sender: sender)
        if let model = await classify(subject: subject, body: body) { verdict = model }

        triageCache[key] = verdict
        if triageCache.count > 300 { triageCache.removeAll() }
        return verdict
    }

    private func classify(subject: String, body: String) async -> MailTriage? {
        #if canImport(FoundationModels)
        if #available(macOS 26.0, *) {
            guard case .available = SystemLanguageModel.default.availability else {
                return nil
            }
            let session = LanguageModelSession(instructions: """
            You sort an email into exactly one category and answer with that single             word and nothing else.
            Decide by what the reader must do, not by how the message sounds.
            urgent: the reader must act soon or something goes wrong. A named deadline, something broken or overdue, or a security event they must shut down.
            reply: a person asked the reader a question or made a request that deserves a written answer, but nothing goes wrong if it waits.
            notice: it only tells the reader something. Receipts, reports, confirmations that an action already happened, and alerts that merely say review this if it was not you. Optional review is not urgent.
            bulk: marketing, a newsletter, an event promotion, or any mass mailing.
            """)
            let prompt = "Subject: \(subject)\n\n\(body.prefix(900))"
            guard let response = try? await session.respond(to: prompt) else { return nil }
            let word = response.content
                .lowercased()
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .components(separatedBy: CharacterSet.alphanumerics.inverted)
                .first { !$0.isEmpty } ?? ""
            return MailTriage(rawValue: word)
        }
        #endif
        return nil
    }

    func replyDraft(subject: String, body: String, sender: String) async -> String {
        #if canImport(FoundationModels)
        if #available(macOS 26.0, *) {
            guard case .available = SystemLanguageModel.default.availability else {
                return ""
            }
            let session = LanguageModelSession(instructions: """
            You write the body of a short reply to an email, three sentences at most.             Answer what was asked, plainly and politely. Write only the body, with no             subject line, no greeting line beyond a simple one, and no sign off. Never             promise a date, a figure, or a fact that is not in the message. Where the             answer depends on something you cannot know, say it plainly instead of             inventing it.
            """)
            let prompt = "From: \(sender)\nSubject: \(subject)\n\n\(body.prefix(1100))"
            guard let response = try? await session.respond(to: prompt) else { return "" }
            return response.content.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        #endif
        return ""
    }

    nonisolated static func heuristic(subject: String, body: String,
                                      sender: String) -> MailTriage {
        let haystack = (subject + " " + body).lowercased()
        let from = sender.lowercased()

        let noreply = ["noreply", "no-reply", "donotreply", "notifications@",
                       "mailer", "newsletter", "marketing"]
        if noreply.contains(where: { from.contains($0) }) {
            let alerting = ["security", "sign-in", "sign in", "suspicious", "password",
                            "verify", "expired", "failed", "declined"]
            return alerting.contains(where: { haystack.contains($0) }) ? .urgent : .notice
        }

        let pressing = ["urgent", "asap", "today", "deadline", "overdue", "immediately",
                        "as soon as possible", "reminder:"]
        if pressing.contains(where: { haystack.contains($0) }) { return .urgent }
        if haystack.contains("?") { return .reply }
        return .notice
    }

    nonisolated static func extractive(_ body: String) -> String {
        let sentences = body
            .replacingOccurrences(of: "\n", with: " ")
            .components(separatedBy: CharacterSet(charactersIn: ".!?"))
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { $0.count > 18 }

        let head = sentences.prefix(2).joined(separator: ". ")
        guard !head.isEmpty else { return String(body.prefix(140)) }
        return head.count > 180 ? String(head.prefix(180)) + "..." : head + "."
    }
}
