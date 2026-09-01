import Foundation
import Security

enum KeychainHelper {

    static func save(
        _ value: String,
        for key: String
    ) {
        let data = Data(value.utf8)

        let query: [String: Any] = [
            kSecClass as String:
                kSecClassGenericPassword,
            kSecAttrAccount as String:
                key
        ]

        SecItemDelete(
            query as CFDictionary
        )

        var attributes = query

        attributes[
            kSecValueData as String
        ] = data

        SecItemAdd(
            attributes as CFDictionary,
            nil
        )
    }


    static func read(
        _ key: String
    ) -> String? {

        let query: [String: Any] = [
            kSecClass as String:
                kSecClassGenericPassword,

            kSecAttrAccount as String:
                key,

            kSecReturnData as String:
                true,

            kSecMatchLimit as String:
                kSecMatchLimitOne
        ]

        var result: AnyObject?

        let status = SecItemCopyMatching(
            query as CFDictionary,
            &result
        )

        guard
            status == errSecSuccess,
            let data = result as? Data,
            let value = String(
                data: data,
                encoding: .utf8
            )
        else {
            return nil
        }

        return value
    }


    static func delete(
        _ key: String
    ) {

        let query: [String: Any] = [
            kSecClass as String:
                kSecClassGenericPassword,

            kSecAttrAccount as String:
                key
        ]

        SecItemDelete(
            query as CFDictionary
        )
    }
}
