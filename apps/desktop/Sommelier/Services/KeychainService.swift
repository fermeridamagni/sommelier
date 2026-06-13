import Foundation
import Security

/// A lightweight wrapper around the macOS Keychain for storing sensitive strings.
///
/// Used to persist API keys (SteamGridDB, Steam Web API) and authentication
/// tokens securely. Each item is stored as a `kSecClassGenericPassword` entry
/// scoped to the `com.sommelier.app` service identifier, ensuring items are
/// isolated from other apps.
///
/// This is a simple synchronous API because Keychain operations complete
/// in microseconds and are safe to call from any thread.
enum KeychainService {
    /// The Keychain service identifier for all Sommelier entries.
    private static let serviceName = "com.sommelier.app"

    /// Saves a string value to the Keychain under the given key.
    ///
    /// If an entry with the same key already exists, it is updated in place
    /// to avoid duplicate-item errors (`errSecDuplicateItem`).
    ///
    /// - Parameters:
    ///   - key: The unique identifier for this Keychain entry (used as `kSecAttrAccount`).
    ///   - value: The string value to store.
    ///   - service: The Keychain service name. Defaults to `com.sommelier.app`.
    /// - Throws: A descriptive error if the Keychain operation fails.
    @discardableResult
    static func save(key: String, value: String, service: String? = nil) throws -> Bool {
        guard let data = value.data(using: .utf8) else {
            throw KeychainError.encodingFailed
        }

        let resolvedService = service ?? serviceName

        // Build the query for an existing item.
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: resolvedService,
            kSecAttrAccount as String: key,
        ]

        // Try to update first — this avoids errSecDuplicateItem.
        let updateAttributes: [String: Any] = [
            kSecValueData as String: data,
        ]

        let updateStatus = SecItemUpdate(query as CFDictionary, updateAttributes as CFDictionary)

        if updateStatus == errSecSuccess {
            return true
        }

        if updateStatus == errSecItemNotFound {
            // Item doesn't exist yet — add it.
            var addQuery = query
            addQuery[kSecValueData as String] = data

            let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
            guard addStatus == errSecSuccess else {
                throw KeychainError.operationFailed(status: addStatus)
            }
            return true
        }

        throw KeychainError.operationFailed(status: updateStatus)
    }

    /// Reads a string value from the Keychain for the given key.
    ///
    /// - Parameters:
    ///   - key: The unique identifier for the Keychain entry.
    ///   - service: The Keychain service name. Defaults to `com.sommelier.app`.
    /// - Returns: The stored string, or `nil` if no entry exists for this key.
    static func read(key: String, service: String? = nil) -> String? {
        let resolvedService = service ?? serviceName

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: resolvedService,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess,
              let data = result as? Data,
              let string = String(data: data, encoding: .utf8) else {
            return nil
        }

        return string
    }

    /// Deletes a Keychain entry for the given key.
    ///
    /// No-op if the entry doesn't exist (returns `true` in that case).
    ///
    /// - Parameters:
    ///   - key: The unique identifier for the Keychain entry.
    ///   - service: The Keychain service name. Defaults to `com.sommelier.app`.
    /// - Throws: A descriptive error if deletion fails for a reason other
    ///   than the item not existing.
    @discardableResult
    static func delete(key: String, service: String? = nil) throws -> Bool {
        let resolvedService = service ?? serviceName

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: resolvedService,
            kSecAttrAccount as String: key,
        ]

        let status = SecItemDelete(query as CFDictionary)

        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.operationFailed(status: status)
        }

        return true
    }

    // MARK: - Well-Known Keys

    /// Well-known Keychain key names used throughout the app.
    enum Keys {
        /// The SteamGridDB API key for artwork fetching.
        static let steamGridDBAPIKey = "steamgriddb_api_key"

        /// The Steam Web API key for game library queries.
        static let steamWebAPIKey = "steam_web_api_key"

        /// The user's Steam 64-bit ID.
        static let steamID = "steam_id"
    }
}

/// Errors specific to Keychain operations.
enum KeychainError: Error, LocalizedError {
    /// The string value couldn't be encoded to UTF-8 data.
    case encodingFailed

    /// A Security framework operation returned an unexpected status code.
    case operationFailed(status: OSStatus)

    var errorDescription: String? {
        switch self {
        case .encodingFailed:
            "Failed to encode the value as UTF-8 data."
        case .operationFailed(let status):
            "Keychain operation failed with status \(status): \(SecCopyErrorMessageString(status, nil) as String? ?? "Unknown error")"
        }
    }
}
