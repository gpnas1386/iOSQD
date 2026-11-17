//
//  ASN1.swift
//  TVRemote
//
//  ASN.1 DER 编解码工具：用于生成自签名 X.509 证书、解析 RSA 公钥
//

import Foundation
import Security

enum ASN1 {
    // MARK: - DER 编码（用于构造 X.509 证书）

    static func tagged(_ tag: UInt8, _ value: Data) -> Data {
        Data([tag]) + length(value.count) + value
    }

    static func sequence(_ value: Data) -> Data { tagged(0x30, value) }
    static func set(_ value: Data) -> Data { tagged(0x31, value) }
    static func oid(_ value: [UInt8]) -> Data { tagged(0x06, Data(value)) }
    static func nullValue() -> Data { Data([0x05, 0x00]) }
    static func utf8(_ value: String) -> Data { tagged(0x0C, Data(value.utf8)) }
    static func bitString(_ value: Data) -> Data { tagged(0x03, Data([0]) + value) }

    static func integer(_ value: Data) -> Data {
        var bytes = value
        // 去掉多余的 0 前缀（保留符号位）
        while bytes.count > 1 && bytes[0] == 0 && bytes[1] & 0x80 == 0 {
            bytes.removeFirst()
        }
        // 最高位为 1 时补 0 表示正数
        if let first = bytes.first, first & 0x80 != 0 {
            bytes.insert(0, at: 0)
        }
        return tagged(0x02, bytes)
    }

    static func utcTime(_ date: Date) -> Data {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyMMddHHmmss'Z'"
        return tagged(0x17, Data(formatter.string(from: date).utf8))
    }

    static func length(_ value: Int) -> Data {
        if value < 128 { return Data([UInt8(value)]) }
        var bytes: [UInt8] = []
        var remaining = value
        while remaining > 0 {
            bytes.insert(UInt8(remaining & 0xFF), at: 0)
            remaining >>= 8
        }
        return Data([0x80 | UInt8(bytes.count)] + bytes)
    }

    // MARK: - 解析 RSA 公钥（提取 modulus 和 exponent）

    static func rsaNumbers(_ key: SecKey) -> (modulus: Data, exponent: Data)? {
        var error: Unmanaged<CFError>?
        guard let raw = SecKeyCopyExternalRepresentation(key, &error) as Data? else {
            return nil
        }
        var reader = Reader(data: raw)
        guard let sequence = reader.element(tag: 0x30) else { return nil }
        var inner = Reader(data: sequence)
        guard var modulus = inner.element(tag: 0x02),
              var exponent = inner.element(tag: 0x02) else { return nil }
        while modulus.first == 0 { modulus.removeFirst() }
        while exponent.count > 1 && exponent.first == 0 { exponent.removeFirst() }
        return (modulus, exponent)
    }

    private struct Reader {
        let data: Data
        var offset = 0

        mutating func element(tag: UInt8) -> Data? {
            guard offset < data.count, data[offset] == tag else { return nil }
            offset += 1
            guard offset < data.count else { return nil }
            var length = Int(data[offset])
            offset += 1
            if length & 0x80 != 0 {
                let count = length & 0x7f
                length = 0
                guard count > 0, offset + count <= data.count else { return nil }
                for _ in 0..<count {
                    length = (length << 8) | Int(data[offset])
                    offset += 1
                }
            }
            guard offset + length <= data.count else { return nil }
            let result = data.subdata(in: offset..<(offset + length))
            offset += length
            return result
        }
    }
}
