import Foundation
import CoreFoundation

nonisolated struct TextEncoding: Equatable, Sendable, Codable {
    let rawValue: UInt
    let displayName: String
    let byteOrderMark: Data

    static let utf8 = TextEncoding(rawValue: String.Encoding.utf8.rawValue, displayName: "UTF-8")
    static let utf8BOM = TextEncoding(rawValue: String.Encoding.utf8.rawValue, displayName: "UTF-8 BOM", byteOrderMark: Data([0xEF, 0xBB, 0xBF]))
    static let gb18030 = TextEncoding(rawValue: CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(CFStringEncodings.GB_18030_2000.rawValue)), displayName: "GB18030")
    static let utf16LittleEndian = TextEncoding(
        rawValue: String.Encoding.utf16LittleEndian.rawValue,
        displayName: "UTF-16 LE",
        byteOrderMark: Data([0xFF, 0xFE])
    )
    static let utf16BigEndian = TextEncoding(
        rawValue: String.Encoding.utf16BigEndian.rawValue,
        displayName: "UTF-16 BE",
        byteOrderMark: Data([0xFE, 0xFF])
    )
    static let ascii = TextEncoding(rawValue: String.Encoding.ascii.rawValue, displayName: "ASCII")

    init(rawValue: UInt, displayName: String, byteOrderMark: Data = Data()) {
        self.rawValue = rawValue
        self.displayName = displayName
        self.byteOrderMark = byteOrderMark
    }

    func encode(_ text: String) -> Data? {
        guard let body = text.data(
            using: String.Encoding(rawValue: rawValue),
            allowLossyConversion: false
        ) else {
            return nil
        }
        return byteOrderMark + body
    }
}
