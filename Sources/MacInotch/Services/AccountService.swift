import AppKit
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

    var hostBundleIds: [String] {
        switch self {
        case .codex: return ["com.openai.codex", "com.openai.chat"]
        case .claude: return ["com.anthropic.claudefordesktop"]
        }
    }

    var processName: String {
        switch self {
        case .codex: return "codex"
        case .claude: return "claude"
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
    var savedAt: Date?
    var knownPercent: Double?
    var knownResetsAt: Date?
    var knownAt: Date?

    var effectivePercent: Double? {
        guard let knownPercent else { return nil }
        if let knownResetsAt, knownResetsAt <= Date() { return 0 }
        return knownPercent
    }

    var usageText: String? {
        guard let percent = effectivePercent, let knownAt else { return nil }
        if percent == 0 { return "0% used, window has reset" }

        let age = Int(Date().timeIntervalSince(knownAt))
        let ago = age < 3600 ? "\(max(1, age / 60))m ago" : "\(age / 3600)h ago"
        var text = "\(Int(percent))% as of \(ago)"

        if let resets = knownResetsAt, resets > Date() {
            let left = Int(resets.timeIntervalSinceNow)
            let span = left >= 3600
                ? "\(left / 3600)h \(left % 3600 / 60)m" : "\(max(1, left / 60))m"
            text += ", resets in \(span)"
        }
        return text
    }

    func subtitle(showEmail: Bool) -> String {
        let planText = plan.isEmpty ? "" : plan.capitalized
        guard showEmail, !email.isEmpty else { return planText }
        return planText.isEmpty ? email : "\(email) · \(planText)"
    }

    var isStale: Bool {
        guard let savedAt else { return false }
        return Date().timeIntervalSince(savedAt) > 60 * 60 * 24 * 25
    }
}

enum AccountError: LocalizedError {
    case noSession(AccountProvider)
    case unreadable
    case keychain(OSStatus)
    case notStored
    case writeFailed
    case providerRunning(AccountProvider)
    case damaged
    case stillRunning(AccountProvider)

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
        case .stillRunning(let provider):
            return "\(provider.title) would not quit, so nothing was changed."
        case .damaged:
            return "The saved session is not usable. Sign in again and save it afresh."
        case .providerRunning(let provider):
            return "Quit \(provider.title) first. It holds this session in memory and "
                + "writes it back on exit, which undoes the switch and can invalidate "
                + "both sign ins."
        }
    }
}

struct Envelope: Codable {
    var version: Int
    var credential: Data
    var sidecar: Data?
}

@MainActor
final class AccountService: ObservableObject {
    static let shared = AccountService()

    @Published fileprivate(set) var accounts: [SavedAccount] = []
    @Published private(set) var activeId: [AccountProvider: String] = [:]
    @Published private(set) var currentEmail: [AccountProvider: String] = [:]
    @Published var lastError: String = ""
    @Published var pendingSwitch: String?
    @Published var busy: Bool = false

    private let service = "io.macinotch.accounts"
    private let legacyService = "io.macinotch.codex-accounts"
    private let metadataURL: URL
    private var watchdog: Timer?
    private var lastSeenStamp: [AccountProvider: Date] = [:]
    private var switchedAt: [AccountProvider: Date] = [:]
    private var lastWritten: [String: Int] = [:]
    private var resetAnnounced: Set<String> = []

    private init() {
        let dir = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("MacInotch", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        metadataURL = dir.appendingPathComponent("accounts.json")
        load()
        discardUntrustedReadings()
        refresh()
    }

    func start() {
        watchdog?.invalidate()
        watchdog = Timer.scheduledTimer(withTimeInterval: 20, repeats: true) { _ in
            Task { @MainActor in
                AccountService.shared.refresh()
                AccountService.shared.checkParkedResets()
            }
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

    private var demoLocked = false

    func refresh() {
        guard !demoLocked else { return }
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

            let fingerprint = data.hashValue
            guard lastWritten[match.id] != fingerprint else { return }
            lastWritten[match.id] = fingerprint

            let box = envelope(for: provider, credential: data)
            Task.detached(priority: .utility) {
                let ok = (try? Self.writeKeychainOffMain(id: match.id,
                                                         envelope: box)) != nil
                guard ok else { return }
                await MainActor.run {
                    let store = AccountService.shared
                    guard let index = store.accounts.firstIndex(
                        where: { $0.id == match.id }) else { return }
                    store.accounts[index].savedAt = Date()
                    store.save()
                }
            }
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
            profile.savedAt = Date()
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
                                       lastUsedAt: Date(),
                                       savedAt: Date())
            try writeKeychain(id: profile.id, envelope: box)
            accounts.append(profile)
        }
        save()
        refresh(provider)
    }

    func activate(_ id: String, force: Bool = false) throws {
        guard let index = accounts.firstIndex(where: { $0.id == id }) else {
            throw AccountError.notStored
        }
        let provider = accounts[index].provider
        guard force || !Self.isRunning(provider) else {
            throw AccountError.providerRunning(provider)
        }
        guard let box = readKeychain(id: id) else { throw AccountError.notStored }
        guard Self.looksUsable(provider, credential: box.credential) else {
            throw AccountError.damaged
        }

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
        switchedAt[provider] = Date()
        save()
        lastSeenStamp[provider] = nil
        refresh(provider)
    }

    func attemptActivate(_ id: String) {
        do {
            try activate(id)
            lastError = ""
        } catch {
            lastError = error.localizedDescription
            FileHandle.standardError.write(
                Data("macinotch: account switch failed, \(error)\n".utf8))
        }
    }

    func attemptCapture(_ provider: AccountProvider, label: String) {
        do {
            try capture(provider, label: label)
            lastError = ""
        } catch {
            lastError = error.localizedDescription
            FileHandle.standardError.write(
                Data("macinotch: account save failed, \(error)\n".utf8))
        }
    }

    static func looksUsable(_ provider: AccountProvider, credential: Data) -> Bool {
        guard !credential.isEmpty,
              let root = try? JSONSerialization.jsonObject(with: credential)
                  as? [String: Any] else { return false }
        guard provider == .codex else { return !root.isEmpty }
        guard let tokens = root["tokens"] as? [String: Any] else { return false }
        let refresh = tokens["refresh_token"] as? String ?? ""
        return !refresh.isEmpty
    }

    static func hostApps(_ provider: AccountProvider) -> [NSRunningApplication] {
        NSWorkspace.shared.runningApplications.filter {
            guard let id = $0.bundleIdentifier else { return false }
            return provider.hostBundleIds.contains(id)
        }
    }

    func requestActivate(_ id: String) {
        guard let account = accounts.first(where: { $0.id == id }) else { return }
        lastError = ""
        if Self.isRunning(account.provider) {
            pendingSwitch = id
        } else {
            attemptActivate(id)
        }
    }

    func cancelPending() { pendingSwitch = nil }

    func confirmPending() {
        guard let id = pendingSwitch else { return }
        pendingSwitch = nil
        Task { await restartAndActivate(id) }
    }

    func restartAndActivate(_ id: String) async {
        guard let account = accounts.first(where: { $0.id == id }) else { return }
        let provider = account.provider

        busy = true
        lastError = ""
        defer { busy = false }

        let apps = Self.hostApps(provider)
        let bundleIds = apps.compactMap(\.bundleIdentifier)
        var watched = Set(apps.map(\.processIdentifier))
        watched.formUnion(PresenceService.pids(named: provider.processName))

        for app in apps { app.terminate() }
        for pid in PresenceService.pids(named: provider.processName) {
            kill(pid, SIGTERM)
        }

        let deadline = Date().addingTimeInterval(20)
        while Date() < deadline, Self.anyAlive(watched) {
            try? await Task.sleep(nanoseconds: 300_000_000)
        }
        if Self.anyAlive(watched) {
            for app in Self.hostApps(provider) where watched.contains(
                app.processIdentifier) {
                app.forceTerminate()
            }
            for pid in watched where kill(pid, 0) == 0 { kill(pid, SIGKILL) }
            try? await Task.sleep(nanoseconds: 1_500_000_000)
        }

        if Self.anyAlive(watched) {
            lastError = AccountError.stillRunning(provider).localizedDescription
        } else {
            do { try activate(id, force: true) }
            catch { lastError = error.localizedDescription }
        }

        for bundle in bundleIds {
            guard let url = NSWorkspace.shared
                .urlForApplication(withBundleIdentifier: bundle) else { continue }
            _ = try? await NSWorkspace.shared.openApplication(
                at: url, configuration: NSWorkspace.OpenConfiguration())
        }
    }

    static func anyAlive(_ pids: Set<pid_t>) -> Bool {
        pids.contains { kill($0, 0) == 0 }
    }

    static func isRunning(_ provider: AccountProvider) -> Bool {
        switch provider {
        case .codex, .claude:
            if !hostApps(provider).isEmpty { return true }
            return PresenceService.processExists(named: provider.processName)
        }
    }

    private func discardUntrustedReadings() {
        guard Prefs.shared.d.accountUsageSchema < 2 else { return }
        Prefs.shared.d.accountUsageSchema = 2
        guard !accounts.isEmpty else { return }

        for index in accounts.indices {
            accounts[index].knownPercent = nil
            accounts[index].knownResetsAt = nil
            accounts[index].knownAt = nil
        }
        save()
    }

    nonisolated static func storedIdentifiers() -> [String] {
        var request: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "io.macinotch.accounts",
            kSecReturnAttributes as String: true,
            kSecMatchLimit as String: kSecMatchLimitAll,
        ]
        request[kSecAttrSynchronizable as String] = false

        var item: CFTypeRef?
        guard SecItemCopyMatching(request as CFDictionary, &item) == errSecSuccess,
              let rows = item as? [[String: Any]] else { return [] }
        return rows.compactMap { $0[kSecAttrAccount as String] as? String }
    }

    var orphanCount: Int {
        let known = Set(accounts.map(\.id))
        return Self.storedIdentifiers().filter { !known.contains($0) }.count
    }

    func recoverFromKeychain() {
        let known = Set(accounts.map(\.id))
        let orphans = Self.storedIdentifiers().filter { !known.contains($0) }
        guard !orphans.isEmpty else {
            lastError = "Nothing unlisted was found in the keychain."
            return
        }

        var recovered = 0
        for id in orphans {
            guard let box = readKeychain(id: id) else { continue }

            let provider: AccountProvider =
                Self.looksUsable(.codex, credential: box.credential) ? .codex : .claude
            let identity = identity(provider, credential: box.credential,
                                    sidecar: box.sidecar)

            accounts.append(SavedAccount(
                id: id,
                provider: provider,
                label: identity.email.isEmpty ? "Recovered account" : identity.email,
                email: identity.email,
                plan: identity.plan,
                accountId: identity.accountId,
                addedAt: Date(),
                lastUsedAt: nil,
                savedAt: Date()))
            recovered += 1
        }

        save()
        refresh()
        lastError = recovered > 0 ? "" : "Those keychain entries could not be read."
    }

    func clearReading(_ id: String) {
        guard let index = accounts.firstIndex(where: { $0.id == id }) else { return }
        accounts[index].knownPercent = nil
        accounts[index].knownResetsAt = nil
        accounts[index].knownAt = nil
        save()
    }

    func recordUsage(_ provider: AccountProvider, percent: Double,
                     resetsAt: Date, measuredAt: Date) {
        guard let id = activeId[provider],
              let index = accounts.firstIndex(where: { $0.id == id }) else { return }

        if let switched = switchedAt[provider], measuredAt <= switched { return }

        guard accounts[index].knownPercent != percent
                || accounts[index].knownResetsAt != resetsAt else { return }
        accounts[index].knownPercent = percent
        accounts[index].knownResetsAt = resetsAt
        accounts[index].knownAt = measuredAt
        save()
    }

    func checkParkedResets() {
        guard Prefs.shared.d.notifyOnUsageReset else { return }

        for index in accounts.indices {
            let account = accounts[index]
            guard let resets = account.knownResetsAt, resets <= Date(),
                  (account.knownPercent ?? 0) > 0,
                  activeId[account.provider] != account.id else { continue }

            let key = "\(account.id)-\(resets.timeIntervalSince1970)"
            guard !resetAnnounced.contains(key) else { continue }
            resetAnnounced.insert(key)

            accounts[index].knownPercent = 0
            accounts[index].knownAt = Date()
            accounts[index].knownResetsAt = nil
            save()

            var p = NotchPayload()
            p.source = account.provider.source.rawValue
            p.kind = "success"
            p.key = "parked-reset-\(account.id)"
            p.title = "\(account.label) has reset"
            p.body = "That account is back to zero. Switch to it when you need it."
            p.timeout = 12
            p.sound = true
            p.actions = [NotchAction(label: "Switch to it",
                                     url: "macinotch://switch?account=\(account.id)")]
            NotchState.shared.handle(p)
        }
    }

    func alternative(to provider: AccountProvider) -> SavedAccount? {
        let current = activeId[provider]
        return accounts(for: provider)
            .filter { $0.id != current }
            .filter { ($0.effectivePercent ?? 100) < 80 }
            .min { ($0.effectivePercent ?? 100) < ($1.effectivePercent ?? 100) }
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

    private func query(id: String, in store: String? = nil) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: store ?? service,
         kSecAttrAccount as String: id,
         kSecAttrSynchronizable as String: false]
    }

    nonisolated static func writeKeychainOffMain(id: String,
                                                 envelope box: Envelope) throws {
        guard let data = try? JSONEncoder().encode(box) else {
            throw AccountError.unreadable
        }
        let base: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "io.macinotch.accounts",
            kSecAttrAccount as String: id,
            kSecAttrSynchronizable as String: false,
        ]
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
        if let data = rawKeychain(id: id, in: service) { return decode(data) }

        guard let legacy = rawKeychain(id: id, in: legacyService) else { return nil }
        let box = decode(legacy)
        if let box { try? writeKeychain(id: id, envelope: box) }
        return box
    }

    private func rawKeychain(id: String, in store: String) -> Data? {
        var request = query(id: id, in: store)
        request[kSecReturnData as String] = true
        request[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        guard SecItemCopyMatching(request as CFDictionary, &item) == errSecSuccess else {
            return nil
        }
        return item as? Data
    }

    private func decode(_ data: Data) -> Envelope? {
        if let box = try? JSONDecoder().decode(Envelope.self, from: data),
           !box.credential.isEmpty {
            return box
        }
        guard (try? JSONSerialization.jsonObject(with: data)) != nil else { return nil }
        return Envelope(version: 0, credential: data, sidecar: nil)
    }

    func hasStoredSecret(_ id: String) -> Bool {
        rawKeychain(id: id, in: service) != nil
            || rawKeychain(id: id, in: legacyService) != nil
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

    fileprivate func save() {
        guard !demoLocked else { return }
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

    func identity(_ provider: AccountProvider, credential: Data,
                  sidecar: Data? = nil) -> Identity {
        switch provider {
        case .codex: return Self.codexIdentity(credential)
        case .claude: return Self.claudeIdentity(sidecar: sidecar)
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

    static func claudeIdentity(sidecar: Data? = nil) -> Identity {
        var identity = Identity()
        let raw: Data?
        if let sidecar {
            raw = sidecar
        } else if let url = AccountProvider.claude.sidecarURL {
            raw = try? Data(contentsOf: url)
        } else {
            raw = nil
        }
        guard let raw,
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

    func loadDemo(_ items: [SavedAccount], active: String) {
        demoLocked = true
        accounts = items
        activeId[.codex] = active
        currentEmail[.codex] = items.first { $0.id == active }?.email ?? ""
        stop()
    }

}
