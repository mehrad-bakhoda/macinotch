import Foundation
import Security

enum AccountProvider: String, Codable, CaseIterable, Identifiable {
    case codex
    case claude

    var id: String { rawValue }

    var title: String {
        switch self {
        case .codex: return "Codex"
        case .claude: return "Claude Code"
        }
    }

    var source: NotchSource {
        switch self {
        case .codex: return .chatgpt
        case .claude: return .claude
        }
    }

    var credentialURL: URL {
        switch self {
        case .codex:
            return URL(fileURLWithPath: NSHomeDirectory() + "/.codex/auth.json")
        case .claude:
            return URL(fileURLWithPath: NSHomeDirectory() + "/.claude/.credentials.json")
        }
    }

    var sidecarURL: URL? {
        switch self {
        case .codex: return nil
        case .claude: return URL(fileURLWithPath: NSHomeDirectory() + "/.claude.json")
        }
    }

    var loginHint: String {
        switch self {
        case .codex: return "codex login"
        case .claude: return "claude then /login"
        }
    }

    var restartHint: String {
        switch self {
        case .codex: return "Restart any running codex session after switching."
        case .claude: return "Restart any running claude session after switching."
        }
    }
}

struct SavedAccount: Identifiable, Codable, Equatable {
    var id: String
    var provider: AccountProvider
    var label: String
    var email: String
    var plan: String
    var accountId: String
    var addedAt: Date
    var lastUsedAt: Date?

    var subtitle: String {
        let planText = plan.isEmpty ? "" : plan.capitalized
        if email.isEmpty { return planText }
        return planText.isEmpty ? email : "\(email) · \(planText)"
    }
}

enum AccountError: LocalizedError {
    case noSession(AccountProvider)
    case unreadable
    case keychain(OSStatus)
    case notStored
    case writeFailed

    var errorDescription: String? {
        switch self {
        case .noSession(let provider):
            return "No \(provider.title) session on disk. Sign in with "
                + "\(provider.loginHint) first."
        case .unreadable:
            return "That session file could not be read."
        case .keychain(let status):
            return "Keychain refused the request (\(status))."
        case .notStored:
            return "That account is no longer in the keychain."
        case .writeFailed:
            return "The session file could not be replaced."
        }
    }
}

private struct Envelope: Codable {
    var version: Int
    var credential: Data
    var sidecar: Data?
}

@MainActor
final class AccountService: ObservableObject {
    static let shared = AccountService()

    @Published private(set) var accounts: [SavedAccount] = []
    @Published private(set) var activeId: [AccountProvider: String] = [:]
    @Published private(set) var currentEmail: [AccountProvider: String] = [:]
    @Published var lastError: String = ""

    private let service = "io.macinotch.accounts"
    private let metadataURL: URL
    private var watchdog: Timer?
    private var lastSeenStamp: [AccountProvider: Date] = [:]

    private init() {
        let dir = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("MacInotch", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        metadataURL = dir.appendingPathComponent("accounts.json")
        load()
        refresh()
    }

    func start() {
        watchdog?.invalidate()
        watchdog = Timer.scheduledTimer(withTimeInterval: 20, repeats: true) { _ in
            Task { @MainActor in AccountService.shared.refresh() }
        }
    }

    func stop() { watchdog?.invalidate(); watchdog = nil }

    func accounts(for provider: AccountProvider) -> [SavedAccount] {
        accounts.filter { $0.provider == provider }
    }

    func hasSession(_ provider: AccountProvider) -> Bool {
        FileManager.default.fileExists(atPath: provider.credentialURL.path)
    }

    var availableProviders: [AccountProvider] {
        AccountProvider.allCases.filter { hasSession($0) || !accounts(for: $0).isEmpty }
    }

    func refresh() {
        for provider in AccountProvider.allCases { refresh(provider) }
    }

    private func refresh(_ provider: AccountProvider) {
        guard let data = try? Data(contentsOf: provider.credentialURL) else {
            activeId[provider] = nil
            currentEmail[provider] = ""
            return
        }

        let identity = self.identity(provider, credential: data)
        currentEmail[provider] = identity.email

        let match = accounts.first {
            $0.provider == provider
                && ((!$0.accountId.isEmpty && $0.accountId == identity.accountId)
                    || (!$0.email.isEmpty && $0.email == identity.email))
        }
        activeId[provider] = match?.id

        let stamp = (try? provider.credentialURL
            .resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
        if let match, let stamp, stamp != lastSeenStamp[provider] {
            lastSeenStamp[provider] = stamp
            try? writeKeychain(id: match.id, envelope: envelope(for: provider,
                                                               credential: data))
        }
    }

    func capture(_ provider: AccountProvider, label: String) throws {
        guard hasSession(provider) else { throw AccountError.noSession(provider) }
        guard let data = try? Data(contentsOf: provider.credentialURL) else {
            throw AccountError.unreadable
        }

        let identity = self.identity(provider, credential: data)
        let existing = accounts.firstIndex {
            $0.provider == provider && !$0.accountId.isEmpty
                && $0.accountId == identity.accountId
        }

        let trimmed = label.trimmingCharacters(in: .whitespacesAndNewlines)
        let name = trimmed.isEmpty
            ? (identity.email.isEmpty ? "\(provider.title) account" : identity.email)
            : trimmed
        let box = envelope(for: provider, credential: data)

        if let existing {
            var profile = accounts[existing]
            profile.label = name
            profile.email = identity.email
            profile.plan = identity.plan
            try writeKeychain(id: profile.id, envelope: box)
            accounts[existing] = profile
        } else {
            let profile = SavedAccount(id: UUID().uuidString,
                                       provider: provider,
                                       label: name,
                                       email: identity.email,
                                       plan: identity.plan,
                                       accountId: identity.accountId,
                                       addedAt: Date(),
                                       lastUsedAt: Date())
            try writeKeychain(id: profile.id, envelope: box)
            accounts.append(profile)
        }
        save()
        refresh(provider)
    }

    func activate(_ id: String) throws {
        guard let index = accounts.firstIndex(where: { $0.id == id }) else {
            throw AccountError.notStored
        }
        let provider = accounts[index].provider
        guard let box = readKeychain(id: id) else { throw AccountError.notStored }

        if let current = try? Data(contentsOf: provider.credentialURL) {
            let identity = self.identity(provider, credential: current)
            let known = accounts.first {
                $0.provider == provider && !$0.accountId.isEmpty
                    && $0.accountId == identity.accountId
            }
            if let known {
                try? writeKeychain(id: known.id,
                                   envelope: envelope(for: provider, credential: current))
            } else {
                try? capture(provider, label: identity.email.isEmpty
                             ? "Previous \(provider.title) account" : identity.email)
            }
        }

        try replace(provider.credentialURL, with: box.credential)
        if let sidecar = box.sidecar, let url = provider.sidecarURL {
            try? mergeSidecar(sidecar, into: url)
        }

        accounts[index].lastUsedAt = Date()
        save()
        lastSeenStamp[provider] = nil
        refresh(provider)
    }

    func rename(_ id: String, to label: String) {
        guard let index = accounts.firstIndex(where: { $0.id == id }) else { return }
        let trimmed = label.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        accounts[index].label = trimmed
        save()
    }

    func forget(_ id: String) {
        deleteKeychain(id: id)
        accounts.removeAll { $0.id == id }
        save()
        refresh()
    }

    private func envelope(for provider: AccountProvider, credential: Data) -> Envelope {
        var sidecar: Data?
        if let url = provider.sidecarURL,
           let raw = try? Data(contentsOf: url),
           let root = try? JSONSerialization.jsonObject(with: raw) as? [String: Any] {
            var carried: [String: Any] = [:]
            for key in ["oauthAccount", "userID"] where root[key] != nil {
                carried[key] = root[key]
            }
            if !carried.isEmpty {
                sidecar = try? JSONSerialization.data(withJSONObject: carried)
            }
        }
        return Envelope(version: 1, credential: credential, sidecar: sidecar)
    }

    private func mergeSidecar(_ sidecar: Data, into url: URL) throws {
        guard let carried = try? JSONSerialization.jsonObject(with: sidecar)
                  as? [String: Any],
              let raw = try? Data(contentsOf: url),
              var root = try? JSONSerialization.jsonObject(with: raw) as? [String: Any]
        else { return }

        for (key, value) in carried { root[key] = value }
        guard let merged = try? JSONSerialization.data(withJSONObject: root,
                                                       options: [.prettyPrinted]) else {
            return
        }
        try replace(url, with: merged)
    }

    private func replace(_ url: URL, with data: Data) throws {
        let directory = url.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: directory,
                                                 withIntermediateDirectories: true)
        let temporary = directory
            .appendingPathComponent(".macinotch-swap-\(UUID().uuidString)")

        guard FileManager.default.createFile(
            atPath: temporary.path, contents: data,
            attributes: [.posixPermissions: 0o600]) else {
            throw AccountError.writeFailed
        }

        do {
            _ = try FileManager.default.replaceItemAt(url, withItemAt: temporary)
        } catch {
            try? FileManager.default.removeItem(at: temporary)
            throw AccountError.writeFailed
        }
        try? FileManager.default.setAttributes([.posixPermissions: 0o600],
                                               ofItemAtPath: url.path)
    }

    private func query(id: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: id,
         kSecAttrSynchronizable as String: false]
    }

    private func writeKeychain(id: String, envelope box: Envelope) throws {
        guard let data = try? JSONEncoder().encode(box) else {
            throw AccountError.unreadable
        }
        let base = query(id: id)
        let status = SecItemUpdate(base as CFDictionary,
                                   [kSecValueData as String: data] as CFDictionary)
        if status == errSecSuccess { return }
        if status != errSecItemNotFound { throw AccountError.keychain(status) }

        var insert = base
        insert[kSecValueData as String] = data
        insert[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        insert[kSecAttrLabel as String] = "MacInotch saved account"
        let added = SecItemAdd(insert as CFDictionary, nil)
        guard added == errSecSuccess else { throw AccountError.keychain(added) }
    }

    private func readKeychain(id: String) -> Envelope? {
        var request = query(id: id)
        request[kSecReturnData as String] = true
        request[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        guard SecItemCopyMatching(request as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else { return nil }

        if let box = try? JSONDecoder().decode(Envelope.self, from: data) { return box }
        return Envelope(version: 0, credential: data, sidecar: nil)
    }

    private func deleteKeychain(id: String) {
        SecItemDelete(query(id: id) as CFDictionary)
    }

    private func load() {
        guard let data = try? Data(contentsOf: metadataURL),
              let stored = try? JSONDecoder().decode([SavedAccount].self, from: data) else {
            return
        }
        accounts = stored
    }

    private func save() {
        accounts.sort { $0.addedAt < $1.addedAt }
        guard let data = try? JSONEncoder().encode(accounts) else { return }
        try? data.write(to: metadataURL, options: [.atomic])
        try? FileManager.default.setAttributes([.posixPermissions: 0o600],
                                               ofItemAtPath: metadataURL.path)
    }

    struct Identity {
        var email = ""
        var plan = ""
        var accountId = ""
    }

    func identity(_ provider: AccountProvider, credential: Data) -> Identity {
        switch provider {
        case .codex: return Self.codexIdentity(credential)
        case .claude: return Self.claudeIdentity()
        }
    }

    static func codexIdentity(_ data: Data) -> Identity {
        var identity = Identity()
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tokens = root["tokens"] as? [String: Any] else { return identity }

        identity.accountId = tokens["account_id"] as? String ?? ""

        guard let token = tokens["id_token"] as? String,
              let claims = decodeClaims(token) else { return identity }

        identity.email = claims["email"] as? String ?? ""
        if let auth = claims["https://api.openai.com/auth"] as? [String: Any] {
            identity.plan = auth["chatgpt_plan_type"] as? String ?? ""
            if identity.accountId.isEmpty {
                identity.accountId = auth["chatgpt_account_id"] as? String ?? ""
            }
        }
        return identity
    }

    static func claudeIdentity() -> Identity {
        var identity = Identity()
        guard let url = AccountProvider.claude.sidecarURL,
              let raw = try? Data(contentsOf: url),
              let root = try? JSONSerialization.jsonObject(with: raw) as? [String: Any],
              let account = root["oauthAccount"] as? [String: Any] else { return identity }

        identity.email = account["emailAddress"] as? String ?? ""
        identity.accountId = account["accountUuid"] as? String ?? ""
        let organisation = account["organizationName"] as? String ?? ""
        let tier = account["seatTier"] as? String ?? ""
        identity.plan = organisation.isEmpty ? tier : organisation
        return identity
    }

    private static func decodeClaims(_ token: String) -> [String: Any]? {
        let parts = token.split(separator: ".")
        guard parts.count >= 2 else { return nil }

        var encoded = String(parts[1])
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        while encoded.count % 4 != 0 { encoded.append("=") }

        guard let data = Data(base64Encoded: encoded) else { return nil }
        return try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    }
}
