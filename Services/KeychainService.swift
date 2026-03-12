//
// KeychainService.swift
// 安全存取 Token / 敏感数据到 Keychain
//

import Foundation
import Security

struct KeychainService {

    private static let service = "com.saomiaoji.speedscan"

    // MARK: - 写入
    @discardableResult
    static func save(key: String, value: String) -> Bool {
        guard let data = value.data(using: .utf8) else { return false }

        // 先删除已有项目
        delete(key: key)

        let query: [String: Any] = [
            kSecClass as String       : kSecClassGenericPassword,
            kSecAttrService as String : service,
            kSecAttrAccount as String : key,
            kSecValueData as String   : data,
            // 设备不解锁时不可访问
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlocked
        ]
        let status = SecItemAdd(query as CFDictionary, nil)
        return status == errSecSuccess
    }

    // MARK: - 读取
    static func load(key: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String          : kSecClassGenericPassword,
            kSecAttrService as String    : service,
            kSecAttrAccount as String    : key,
            kSecReturnData as String     : true,
            kSecMatchLimit as String     : kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess,
              let data = item as? Data,
              let value = String(data: data, encoding: .utf8) else {
            return nil
        }
        return value
    }

    // MARK: - 删除
    @discardableResult
    static func delete(key: String) -> Bool {
        let query: [String: Any] = [
            kSecClass as String       : kSecClassGenericPassword,
            kSecAttrService as String : service,
            kSecAttrAccount as String : key
        ]
        let status = SecItemDelete(query as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }
}
