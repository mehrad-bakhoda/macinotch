import Foundation

@MainActor
enum DemoData {
    static var enabled: Bool {
        ProcessInfo.processInfo.environment["MACINOTCH_DEMO"] == "1"
    }

    static func apply() {
        guard enabled else { return }
        NotchState.shared.usage = UsageSnapshot(
            claude: LocalTally(tokens: 412_000, messages: 148,
                               since: minutesAgo(180)),
            codexTally: LocalTally(tokens: 88_400, messages: 63,
                                   since: minutesAgo(140)),
            codexLimits: CodexLimits(
                primary: RateWindow(usedPercent: 84, windowMinutes: 300,
                                    resetsAt: Date().addingTimeInterval(7400)),
                secondary: RateWindow(usedPercent: 31, windowMinutes: 10080,
                                      resetsAt: Date().addingTimeInterval(360_000)),
                plan: "plus", measuredAt: Date(),
                projection: RateProjection(
                    percentPerHour: 11,
                    exhaustionAt: Date().addingTimeInterval(5200))))
        NotchState.shared.sessions = sessions
        MailService.shared.loadDemo(mail)
        AccountService.shared.loadDemo(accounts, active: accounts[1].id)
        GitHubService.shared.loadDemo(github)
    }

    private static func minutesAgo(_ n: Double) -> Date {
        Date().addingTimeInterval(-n * 60)
    }

    static var sessions: [CodeSession] {
        [
            CodeSession(id: "d1", provider: .claude, project: "/Users/dev/atlas",
                        path: "/tmp/d1", updatedAt: minutesAgo(2), messages: 148,
                        tokens: 412_000, model: "opus-4", isLive: true,
                        title: "atlas-checkout"),
            CodeSession(id: "d2", provider: .chatgpt, project: "/Users/dev/ledger",
                        path: "/tmp/d2", updatedAt: minutesAgo(9), messages: 63,
                        tokens: 88_400, model: "gpt-5", isLive: true,
                        title: "Rewrite the billing importer"),
            CodeSession(id: "d3", provider: .claude, project: "/Users/dev/site",
                        path: "/tmp/d3", updatedAt: minutesAgo(96), messages: 27,
                        tokens: 51_200, model: "sonnet-4", isLive: false,
                        title: "site-redesign"),
            CodeSession(id: "d4", provider: .chatgpt, project: "/Users/dev/infra",
                        path: "/tmp/d4", updatedAt: minutesAgo(310), messages: 41,
                        tokens: 63_900, model: "gpt-5", isLive: false,
                        title: "Terraform module cleanup"),
        ]
    }

    static var mail: [MailMessage] {
        [
            MailMessage(id: "m1", sender: "Dana Whitfield",
                        senderAddress: "dana@northlight.co",
                        subject: "Contract clause 4, can you confirm today?",
                        received: minutesAgo(14), flagged: true, account: "Work",
                        preview: "",
                        summary: "Needs your confirmation on clause 4 before signing "
                               + "closes this evening.",
                        triage: .urgent),
            MailMessage(id: "m2", sender: "Priya Raman",
                        senderAddress: "priya@northlight.co",
                        subject: "Re: onboarding copy, one question",
                        received: minutesAgo(48), flagged: false, account: "Work",
                        preview: "",
                        summary: "Asks which of two onboarding headlines you prefer "
                               + "before the build freeze.",
                        triage: .reply),
            MailMessage(id: "m3", sender: "Vercel",
                        senderAddress: "notifications@vercel.com",
                        subject: "Deployment succeeded for atlas",
                        received: minutesAgo(72), flagged: false, account: "Work",
                        preview: "",
                        summary: "Production deployment for atlas finished without "
                               + "errors.",
                        triage: .notice),
        ]
    }

    static var accounts: [SavedAccount] {
        [
            SavedAccount(id: "a1", provider: .codex, label: "Work",
                         email: "dev@northlight.co", plan: "pro",
                         accountId: "acct_work", addedAt: minutesAgo(9000),
                         lastUsedAt: minutesAgo(400), savedAt: minutesAgo(400),
                         knownPercent: 12, knownResetsAt: Date().addingTimeInterval(9000),
                         knownAt: minutesAgo(120)),
            SavedAccount(id: "a2", provider: .codex, label: "Personal",
                         email: "me@fastmail.com", plan: "plus",
                         accountId: "acct_personal", addedAt: minutesAgo(8000),
                         lastUsedAt: minutesAgo(3), savedAt: minutesAgo(3),
                         knownPercent: 84, knownResetsAt: Date().addingTimeInterval(7400),
                         knownAt: minutesAgo(2)),
        ]
    }

    static var github: GitHubSnapshot {
        var snap = GitHubSnapshot()
        snap.login = "northlight"
        snap.pushes = 9
        snap.pullRequests = 2
        snap.reviewRequests = 3
        snap.checkedAt = Date()
        snap.failures = [
            WorkflowFailure(id: 1, repo: "northlight/atlas", workflow: "CI",
                            branch: "main", url: "https://github.com",
                            at: minutesAgo(26)),
        ]

        var days: [ContributionDay] = []
        var seed = 7
        for index in 0..<(52 * 7) {
            seed = (seed &* 1103515245 &+ 12345) & 0x7FFFFFFF
            let bucket = (seed >> 8) % 10
            let level = bucket >= 7 ? 4 : bucket >= 5 ? 3 : bucket >= 3 ? 2
                : bucket >= 1 ? 1 : 0
            days.append(ContributionDay(
                date: Date().addingTimeInterval(Double(index - 364) * 86400),
                count: level * 3, level: level))
        }
        snap.contributions = days
        snap.contributionTotal = 687
        return snap
    }
}
