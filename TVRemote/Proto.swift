//
//  Proto.swift
//  TVRemote
//
//  极简 protobuf 编解码工具（Android TV Remote v2 协议使用）
//

import Foundation

enum Proto {
    // MARK: - 编码

    /// varint 编码
    static func varint(_ value: Int) -> Data {
        var v = UInt64(value)
        var out = Data()
        repeat {
            var byte = UInt8(v & 0x7f)
            v >>= 7
            if v != 0 { byte |= 0x80 }
            out.append(byte)
        } while v != 0
        return out
    }

    /// 字段（varint 值）
    static func varintField(_ number: Int, _ value: Int) -> Data {
        varint(number << 3) + varint(value)
    }

    /// 字段（bytes 值）
    static func bytesField(_ number: Int, _ value: Data) -> Data {
        message(field: number, payload: value)
    }

    /// 字段（string 值）
    static func stringField(_ number: Int, _ value: String) -> Data {
        message(field: number, payload: Data(value.utf8))
    }

    /// 字段（嵌套 message，wire type 2）
    static func message(field: Int, payload: Data) -> Data {
        varint((field << 3) | 2) + varint(payload.count) + payload
    }

    // MARK: - 解码

    /// varint 解码，返回 (值, 占用字节数)
    static func readVarint(_ data: Data, at start: Int) -> (value: Int, size: Int)? {
        var value = 0
        var shift = 0
        var index = start
        while index < data.count && shift < 64 {
            let byte = Int(data[index])
            index += 1
            value |= (byte & 0x7f) << shift
            if byte & 0x80 == 0 {
                return (value, index - start)
            }
            shift += 7
        }
        return nil
    }

    /// 解析顶层字段，返回 [字段号: 字段内容]
    static func fields(_ data: Data) -> [Int: Data] {
        var result: [Int: Data] = [:]
        var index = 0
        while index < data.count {
            guard let (tag, tagSize) = readVarint(data, at: index) else { break }
            index += tagSize
            let number = tag >> 3
            let wire = tag & 7
            if wire == 2 {
                guard let (length, size) = readVarint(data, at: index) else { break }
                index += size
                guard index + length <= data.count else { break }
                result[number] = data.subdata(in: index..<(index + length))
                index += length
            } else if wire == 0 {
                guard let (_, size) = readVarint(data, at: index) else { break }
                result[number] = data.subdata(in: index..<(index + size))
                index += size
            } else {
                break
            }
        }
        return result
    }

    /// 读取某字段的 int 值
    static func intField(_ data: Data, number: Int) -> Int? {
        guard let raw = fields(data)[number] else { return nil }
        return readVarint(raw, at: 0)?.value
    }
}

extension Data {
    /// 从十六进制字符串创建 Data（用于配对码解析）
    init?(hexString: String) {
        let clean = hexString.filter { !$0.isWhitespace }
        guard clean.count % 2 == 0 else { return nil }
        var bytes = [UInt8]()
        var index = clean.startIndex
        while index < clean.endIndex {
            let next = clean.index(index, offsetBy: 2)
            guard let byte = UInt8(clean[index..<next], radix: 16) else { return nil }
            bytes.append(byte)
            index = next
        }
        self = Data(bytes)
    }
}
