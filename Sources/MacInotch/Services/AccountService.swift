import Foundation
import Security

struct CodexAccount: Identifiable, Codable, Equatable {
    var id: String
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
    case noSession
    case unreadable
    case keychain(OSStatus)
    case notStored
    case writeFailed

    var errorDescription: String? {
        switch self {
        case .noSession:
            return "No Codex session found. Run codex login first."
        case .unreadable:
            return "The Codex session file could not be read."
        case .keychain(let status):
            return "Keychain refused the request (\(status))."
        case .notStored:
            return "That account is no longer in the keychain."
        case .writeFailed:
            return "The Codex session file could not be replaced."
        }
    }
}

@MainActor
final class AccountService: ObservableObject {
    static let shared = AccountService()

    @Published private(set) var accounts: [CodexAccount] = []
    @Published private(set) var activeId: String?
    @Published private(set) var currentEmail: String = ""
    @Published var lastError: String = ""

    private let service = "io.macinotch.codex-accounts"
    private let metadataURL: URL
    private let authURL = URL(fileURLWithPath: NSHomeDirectory() + "/.codex/auth.json")
    private var watchdog: Timer?
    private var lastSeenStamp: Date?

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

    var hasCurrentSession: Bool { FileManager.default.fileExists(atPath: authURL.path) }

    func refresh() {
        guard let data = try? Data(contentsOf: authURL) else {
            activeId = nil
            currentEmail = ""
            return
        }

        let identity = Self.identity(from: data)
        currentEmail = identity.email

        let match = accounts.first {
            (!$0.accountId.isEmpty && $0.accountId == identity.accountId)
                || (!$0.email.isEmpty && $0.email == identity.email)
        }
        activeId = match?.id

        let stamp = (try? authURL.resourceValues(forKeys: [.contentModificationDateKey]))?
            .contentModificationDate
        if let match, let stamp, stamp != lastSeenStamp {
            lastSeenStamp = stamp
            try? writeKeychain(id: match.id, data: data)
        }
    }

    func capture(label: String) throws {
        guard FileManager.default.fileExists(atPath: authURL.path) else {
            throw AccountError.noSession
        }
        guard let data = try? Data(contentsOf: authURL) else { throw AccountError.unreadable }

        let identity = Self.identity(from: data)
        let existing = accounts.firstIndex {
            !$0.accountId.isEmpty && $0.accountId == identity.accountId
        }

        let trimmed = label.trimmingCharacters(in: .whitespacesAndNewlines)
        let name = trimmed.isEmpty
            ? (identity.email.isEmpty ? "Codex account" : identity.email)
            : trimmed

        if let existing {
            var profile = accounts[existing]
            profile.label = name
            profile.email = identity.email
            profile.plan = identity.plan
            try writeKeychain(id: profile.id, data: data)
            accounts[existing] = profile
        } else {
            let profile = CodexAccount(id: UUID().uuidString,
                                       label: name,
                                       email: identity.email,
                                       plan: identity.plan,
                                       accountId: identity.accountId,
                                       addedAt: Date(),
                                       lastUsedAt: Date())
            try writeKeychain(id: profile.id, data: data)
            accounts.append(profile)
        }
        save()
        refresh()
    }

    func activate(_ id: String) throws {
        guard let index = accounts.firstIndex(where: { $0.id == id }) else {
            throw AccountError.notStored
        }
        guard let blob = readKeychain(id: id) else { throw AccountError.notStored }

        if let current = try? Data(contentsOf: authURL) {
            let identity = Self.identity(from: current)
            let known = accounts.contains {
                !$0.accountId.isEmpty && $0.accountId == identity.accountId
            }
            if !known {
                try? capture(label: identity.email.isEmpty ? "Previous account"
                                                           : identity.email)
            } else if let active = accounts.first(where: {
                !$0.accountId.isEmpty && $0.accountId == identity.accountId
            }) {
                try? writeKeychain(id: active.id, data: current)
            }
        }

        try replaceAuthFile(with: blob)
        accounts[index].lastUsedAt = Date()
        save()
        lastSeenStamp = nil
        refresh()
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

    private func replaceAuthFile(with data: Data) throws {
        let directory = authURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: directory,
                                                 withIntermediateDirectories: true)
        let temporary = directory.appendingPathComponent(".macinotch-auth-\(UUID().uuidString)")

        guard FileManager.default.createFile(
            atPath: temporary.path, contents: data,
            attributes: [.posixPermissions: 0o600]) else {
            throw AccountError.writeFailed
        }

        do {
            _ = try FileManager.default.replaceItemAt(authURL, withItemAt: temporary)
        } catch {
            try? FileManager.default.removeItem(at: temporary)
            throw AccountError.writeFailed
        }
        try? FileManager.default.setAttributes([.posixPermissions: 0o600],
                                               ofItemAtPath: authURL.path)
    }

    private func query(id: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: id,
         kSecAttrSynchronizable as String: false]
    }

    private func writeKeychain(id: String, data: Data) throws {
        let base = query(id: id)
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
        ]

        let status = SecItemUpdate(base as CFDictionary, attributes as CFDictionary)
        if status == errSecSuccess { return }
        if status != errSecItemNotFound { throw AccountError.keychain(status) }

        var insert = base
        insert[kSecValueData as String] = data
        insert[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        insert[kSecAttrLabel as String] = "MacInotch Codex account"
        let added = SecItemAdd(insert as CFDictionary, nil)
        guard added == errSecSuccess else { throw AccountError.keychain(added) }
    }

    private func readKeychain(id: String) -> Data? {
        var request = query(id: id)
        request[kSecReturnData as String] = true
        request[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        guard SecItemCopyMatching(request as CFDictionary, &item) == errSecSuccess else {
            return nil
        }
        return item as? Data
    }

    private func deleteKeychain(id: String) {
        SecItemDelete(query(id: id) as CFDictionary)
    }

    private func load() {
        guard let data = try? Data(contentsOf: metadataURL),
              let stored = try? JSONDecoder().decode([CodexAccount].self, from: data) else {
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

    static func identity(from data: Data) -> Identity {
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
