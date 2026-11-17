//
//  IdentityStore.swift
//  TVRemote
//
//  在设备上生成并保存 RSA-2048 客户端身份（自签名 X.509 证书 + 私钥），
//  用于 Android TV Remote v2 的 TLS 连接与配对挑战。证书存于 Keychain。
//

import Foundation
import Security

enum IdentityStore {
    private static let certificateLabel = "TV Remote Client Certificate"
    private static let keyTag = Data("com.tvremote.client-key".utf8)

    /// 加载身份，不存在则生成
    static func loadIdentity() -> SecIdentity? {
        if let stored = storedIdentity() { return stored }
        return generateIdentity()
    }

    /// 从身份中取出证书
    static func certificate(from identity: SecIdentity) -> SecCertificate? {
        var certificate: SecCertificate?
        SecIdentityCopyCertificate(identity, &certificate)
        return certificate
    }

    private static func storedIdentity() -> SecIdentity? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassIdentity,
            kSecAttrLabel as String: certificateLabel,
            kSecReturnRef as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess else {
            return nil
        }
        return (result as! SecIdentity?)
    }

    private static func generateIdentity() -> SecIdentity? {
        let attributes: [String: Any] = [
            kSecAttrKeyType as String: kSecAttrKeyTypeRSA,
            kSecAttrKeySizeInBits as String: 2048,
            kSecPrivateKeyAttrs as String: [
                kSecAttrIsPermanent as String: true,
                kSecAttrApplicationTag as String: keyTag,
                kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            ]
        ]
        var error: Unmanaged<CFError>?
        guard let privateKey = SecKeyCreateRandomKey(attributes as CFDictionary, &error),
              let publicKey = SecKeyCopyPublicKey(privateKey),
              let publicDER = SecKeyCopyExternalRepresentation(publicKey, &error) as Data?,
              let certDER = X509.selfSigned(publicKeyPKCS1: publicDER, privateKey: privateKey),
              let certificate = SecCertificateCreateWithData(nil, certDER as CFData) else {
            return nil
        }
        let add: [String: Any] = [
            kSecClass as String: kSecClassCertificate,
            kSecValueRef as String: certificate,
            kSecAttrLabel as String: certificateLabel,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]
        SecItemAdd(add as CFDictionary, nil)
        return storedIdentity()
    }
}

/// 构造自签名 X.509 证书（DER 编码）
private enum X509 {
    static func selfSigned(publicKeyPKCS1: Data, privateKey: SecKey) -> Data? {
        let sha256WithRSA = ASN1.sequence(
            ASN1.oid([0x2A, 0x86, 0x48, 0x86, 0xF7, 0x0D, 0x01, 0x01, 0x0B]) + ASN1.nullValue()
        )
        let rsaAlgorithm = ASN1.sequence(
            ASN1.oid([0x2A, 0x86, 0x48, 0x86, 0xF7, 0x0D, 0x01, 0x01, 0x01]) + ASN1.nullValue()
        )
        let commonName = ASN1.sequence(
            ASN1.set(ASN1.sequence(ASN1.oid([0x55, 0x04, 0x03]) + ASN1.utf8("TV Remote")))
        )

        let now = Date().addingTimeInterval(-86_400)
        let expiry = Calendar(identifier: .gregorian).date(byAdding: .year, value: 10, to: now) ?? now
        let validity = ASN1.sequence(ASN1.utcTime(now) + ASN1.utcTime(expiry))

        let subjectPublicKeyInfo = ASN1.sequence(rsaAlgorithm + ASN1.bitString(publicKeyPKCS1))

        var serial = Data(count: 16)
        _ = serial.withUnsafeMutableBytes {
            SecRandomCopyBytes(kSecRandomDefault, 16, $0.baseAddress!)
        }
        serial[0] &= 0x7F
        if serial.allSatisfy({ $0 == 0 }) { serial[15] = 1 }

        let version = ASN1.tagged(0xA0, ASN1.integer(Data([2])))
        let tbs = ASN1.sequence(
            version + ASN1.integer(serial) + sha256WithRSA + commonName + validity + commonName + subjectPublicKeyInfo
        )

        var error: Unmanaged<CFError>?
        guard let signature = SecKeyCreateSignature(
            privateKey,
            .rsaSignatureMessagePKCS1v15SHA256,
            tbs as CFData,
            &error
        ) as Data? else {
            return nil
        }
        return ASN1.sequence(tbs + sha256WithRSA + ASN1.bitString(signature))
    }
}
