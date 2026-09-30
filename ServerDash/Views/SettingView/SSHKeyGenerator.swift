import Foundation
import Security

/// Creates an exportable RSA key and an OpenSSH authorized_keys line.
enum SSHKeyGenerator {
    static func generate() -> (privateKey: String, publicKey: String)? {
        let attributes: [String: Any] = [
            kSecAttrKeyType as String: kSecAttrKeyTypeRSA,
            kSecAttrKeySizeInBits as String: 3072,
            kSecAttrIsPermanent as String: false,
        ]
        guard let privateKey = SecKeyCreateRandomKey(attributes as CFDictionary, nil),
              let publicKey = SecKeyCopyPublicKey(privateKey),
              let privateDER = SecKeyCopyExternalRepresentation(privateKey, nil) as Data?,
              let publicDER = SecKeyCopyExternalRepresentation(publicKey, nil) as Data?,
              let integers = rsaPublicIntegers(from: publicDER)
        else { return nil }

        let base64 = privateDER.base64EncodedString()
        let lines = stride(from: 0, to: base64.count, by: 64).map { offset -> String in
            let start = base64.index(base64.startIndex, offsetBy: offset)
            let end = base64.index(start, offsetBy: min(64, base64.count - offset))
            return String(base64[start..<end])
        }
        let pem = "-----BEGIN RSA PRIVATE KEY-----\n" + lines.joined(separator: "\n") + "\n-----END RSA PRIVATE KEY-----\n"

        var blob = Data()
        blob.append(sshString(Data("ssh-rsa".utf8)))
        blob.append(sshMPInt(integers.exponent))
        blob.append(sshMPInt(integers.modulus))
        return (pem, "ssh-rsa \(blob.base64EncodedString()) server-dash")
    }

    private static func rsaPublicIntegers(from data: Data) -> (modulus: Data, exponent: Data)? {
        var reader = DERReader(bytes: Array(data))
        guard let sequence = reader.read(tag: 0x30) else { return nil }
        var contents = DERReader(bytes: sequence)
        guard let modulus = contents.read(tag: 0x02),
              let exponent = contents.read(tag: 0x02)
        else { return nil }
        return (Data(modulus), Data(exponent))
    }

    private static func sshMPInt(_ value: Data) -> Data {
        var bytes = Array(value)
        while bytes.count > 1 && bytes[0] == 0 { bytes.removeFirst() }
        if let first = bytes.first, first & 0x80 != 0 { bytes.insert(0, at: 0) }
        return sshString(Data(bytes))
    }

    private static func sshString(_ value: Data) -> Data {
        var length = UInt32(value.count).bigEndian
        var result = withUnsafeBytes(of: &length) { Data($0) }
        result.append(value)
        return result
    }
}

private struct DERReader {
    let bytes: [UInt8]
    var offset = 0

    mutating func read(tag: UInt8) -> [UInt8]? {
        guard offset + 2 <= bytes.count, bytes[offset] == tag else { return nil }
        offset += 1
        let first = Int(bytes[offset])
        offset += 1
        let length: Int
        if first & 0x80 == 0 {
            length = first
        } else {
            let count = first & 0x7f
            guard count > 0, count <= 4, offset + count <= bytes.count else { return nil }
            var parsed = 0
            for _ in 0..<count {
                parsed = (parsed << 8) | Int(bytes[offset])
                offset += 1
            }
            length = parsed
        }
        guard length <= bytes.count - offset else { return nil }
        defer { offset += length }
        return Array(bytes[offset..<(offset + length)])
    }
}
