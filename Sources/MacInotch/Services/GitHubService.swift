import Foundation
import Security

struct WorkflowFailure: Identifiable, Equatable {
    var id: Int
    var repo: String
    var workflow: String
    var branch: String
    var url: String
    var at: Date

    var ago: String {
        let seconds = Int(Date().timeIntervalSince(at))
        if seconds < 3600 { return "\(max(1, seconds / 60))m ago" }
        if seconds < 86400 { return "\(seconds / 3600)h ago" }
        return "\(seconds / 86400)d ago"
    }
}

struct GitHubSnapshot: Equatable {
    var login: String = ""
    var pushes: Int = 0
    var pullRequests: Int = 0
    var reviewRequests: Int = 0
    var failures: [WorkflowFailure] = []
    var checkedAt: Date?

    var connected: Bool { !login.isEmpty }

    var summary: String {
        var parts: [String] = []
        parts.append("\(pushes) push\(pushes == 1 ? "" : "es")")
        if pullRequests > 0 { parts.append("\(pullRequests) PR opened") }
        if reviewRequests > 0 { parts.append("\(reviewRequests) to review") }
        return parts.joined(separator: ", ")
    }
}

@MainActor
final class GitHubService: ObservableObject {
    static let shared = GitHubService()

    @Published private(set) var snapshot = GitHubSnapshot()
    @Published private(set) var busy = false
    @Published var lastError = ""

    private let service = "io.macinotch.github"
    private let account = "token"
    private var timer: Timer?
    private var announced: Set<Int> = []
    private var primed = false

    private init() {}

    var hasToken: Bool { token != nil }

    func start() {
        timer?.invalidate()
        guard hasToken else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 180, repeats: true) { _ in
            Task { @MainActor in await GitHubService.shared.refresh() }
        }
        Task { await refresh() }
    }

    func stop() { timer?.invalidate(); timer = nil }

    func connect(token value: String) {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        store(trimmed)
        lastError = ""
        primed = false
        announced.removeAll()
        start()
    }

    func disconnect() {
        SecItemDelete(query() as CFDictionary)
        stop()
        snapshot = GitHubSnapshot()
        lastError = ""
    }

    private func query() -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: account,
         kSecAttrSynchronizable as String: false]
    }

    private func store(_ value: String) {
        let data = Data(value.utf8)
        let status = SecItemUpdate(query() as CFDictionary,
                                   [kSecValueData as String: data] as CFDictionary)
        guard status != errSecSuccess else { return }

        var insert = query()
        insert[kSecValueData as String] = data
        insert[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        insert[kSecAttrLabel as String] = "MacInotch GitHub token"
        SecItemAdd(insert as CFDictionary, nil)
    }

    private var token: String? {
        var request = query()
        request[kSecReturnData as String] = true
        request[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        guard SecItemCopyMatching(request as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else { return nil }
        return String(decoding: data, as: UTF8.self)
    }

    private func get(_ path: String) async -> Any? {
        guard let token, let url = URL(string: "https://api.github.com" + path) else {
            return nil
        }
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("MacInotch", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 15

        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse else { return nil }

        guard (200..<300).contains(http.statusCode) else {
            lastError = http.statusCode == 401
                ? "GitHub rejected the token."
                : "GitHub returned \(http.statusCode)."
            return nil
        }
        return try? JSONSerialization.jsonObject(with: data)
    }

    func refresh() async {
        guard hasToken, !busy else { return }
        busy = true
        defer { busy = false }

        guard let user = await get("/user") as? [String: Any],
              let login = user["login"] as? String else { return }

        var next = GitHubSnapshot()
        next.login = login
        next.checkedAt = Date()
        lastError = ""

        let since = Calendar.current.startOfDay(for: Date())
        var repos: Set<String> = []

        if let events = await get("/users/\(login)/events?per_page=100") as? [[String: Any]] {
            for event in events {
                guard let stamp = event["created_at"] as? String,
                      let date = UsageService.parseDate(stamp), date >= since else { continue }
                let repo = (event["repo"] as? [String: Any])?["name"] as? String
                if let repo { repos.insert(repo) }

                switch event["type"] as? String {
                case "PushEvent":
                    let payload = event["payload"] as? [String: Any]
                    next.pushes += payload?["size"] as? Int ?? 1
                case "PullRequestEvent":
                    let payload = event["payload"] as? [String: Any]
                    if payload?["action"] as? String == "opened" { next.pullRequests += 1 }
                default: break
                }
            }
        }

        if let search = await get(
            "/search/issues?q=is:open+is:pr+review-requested:\(login)&per_page=1")
            as? [String: Any] {
            next.reviewRequests = search["total_count"] as? Int ?? 0
        }

        var failures: [WorkflowFailure] = []
        for repo in repos.prefix(6) {
            guard let runs = await get(
                "/repos/\(repo)/actions/runs?per_page=8") as? [String: Any],
                  let list = runs["workflow_runs"] as? [[String: Any]] else { continue }

            for run in list {
                guard run["conclusion"] as? String == "failure",
                      let id = run["id"] as? Int,
                      let stamp = run["updated_at"] as? String,
                      let date = UsageService.parseDate(stamp),
                      date >= since.addingTimeInterval(-86_400) else { continue }

                failures.append(WorkflowFailure(
                    id: id,
                    repo: repo,
                    workflow: run["name"] as? String ?? "Workflow",
                    branch: run["head_branch"] as? String ?? "",
                    url: run["html_url"] as? String ?? "",
                    at: date))
            }
        }
        next.failures = failures.sorted { $0.at > $1.at }

        if snapshot != next { snapshot = next }
        announce(next.failures)
    }

    private func announce(_ failures: [WorkflowFailure]) {
        guard Prefs.shared.d.alertWorkflowFailure else { return }
        defer { primed = true }

        for failure in failures where !announced.contains(failure.id) {
            announced.insert(failure.id)
            guard primed else { continue }

            var p = NotchPayload()
            p.source = NotchSource.system.rawValue
            p.kind = "error"
            p.key = "gh-\(failure.id)"
            p.title = "\(failure.workflow) failed"
            p.body = "\(failure.repo)\(failure.branch.isEmpty ? "" : " on \(failure.branch)")"
            p.timeout = 20
            p.sound = true
            p.actions = [NotchAction(label: "Open run", url: failure.url)]
            NotchState.shared.handle(p)
        }
    }
}
