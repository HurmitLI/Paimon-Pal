import Foundation
import Security

struct VaultCredential: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    var label: String
    var account: String
    var secret: String
    var kind: String
    let createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        label: String,
        account: String,
        secret: String,
        kind: String = "账号",
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.label = label
        self.account = account
        self.secret = secret
        self.kind = kind
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

protocol CredentialVaultPersisting {
    func load() throws -> [VaultCredential]
    func save(_ credentials: [VaultCredential]) throws
}

enum CredentialVaultError: LocalizedError {
    case keychain(OSStatus)

    var errorDescription: String? {
        switch self {
        case .keychain(let status):
            return SecCopyErrorMessageString(status, nil) as String?
                ?? "Keychain 错误 \(status)"
        }
    }
}

struct KeychainCredentialVault: CredentialVaultPersisting {
    private let service = "com.notchflow.app.productivity-vault"
    private let account = "workspace-v1"

    func load() throws -> [VaultCredential] {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return [] }
        guard status == errSecSuccess, let data = result as? Data else {
            throw CredentialVaultError.keychain(status)
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode([VaultCredential].self, from: data)
    }

    func save(_ credentials: [VaultCredential]) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(credentials)
        let base: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        let updateStatus = SecItemUpdate(
            base as CFDictionary,
            [kSecValueData as String: data] as CFDictionary
        )
        if updateStatus == errSecSuccess { return }
        guard updateStatus == errSecItemNotFound else {
            throw CredentialVaultError.keychain(updateStatus)
        }
        var addition = base
        addition[kSecValueData as String] = data
        addition[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let addStatus = SecItemAdd(addition as CFDictionary, nil)
        guard addStatus == errSecSuccess else {
            throw CredentialVaultError.keychain(addStatus)
        }
    }
}

@MainActor
final class CredentialVaultController: ObservableObject {
    @Published private(set) var credentials: [VaultCredential] = []
    @Published private(set) var statusText = "密文使用 macOS Keychain 加密保存。"

    private let persistence: CredentialVaultPersisting

    init(persistence: CredentialVaultPersisting = KeychainCredentialVault()) {
        self.persistence = persistence
        do {
            credentials = try persistence.load().sorted { $0.updatedAt > $1.updatedAt }
        } catch {
            statusText = "保险箱无法读取：\(error.localizedDescription)"
        }
    }

    @discardableResult
    func add(label: String, account: String, secret: String, kind: String) -> Bool {
        let cleanLabel = label.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanAccount = account.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanLabel.isEmpty, !secret.isEmpty else {
            statusText = "名称和密文不能为空。"
            return false
        }
        credentials.insert(
            VaultCredential(
                label: String(cleanLabel.prefix(80)),
                account: String(cleanAccount.prefix(160)),
                secret: String(secret.prefix(8_192)),
                kind: String(kind.prefix(24))
            ),
            at: 0
        )
        return persist(success: "已加密保存到本机 Keychain。")
    }

    func delete(id: UUID) {
        let old = credentials
        credentials.removeAll { $0.id == id }
        if !persist(success: "凭据已删除。") {
            credentials = old
        }
    }

    private func persist(success: String) -> Bool {
        do {
            try persistence.save(credentials)
            statusText = success
            return true
        } catch {
            statusText = "保险箱保存失败：\(error.localizedDescription)"
            return false
        }
    }
}
