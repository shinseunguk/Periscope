import Foundation

public struct StorageData {
    public let localStorage: [String: String]
    public let sessionStorage: [String: String]
    public let cookies: String
    public let captureTime: Date
    
    public init(localStorage: [String: String] = [:], 
                sessionStorage: [String: String] = [:], 
                cookies: String = "", 
                captureTime: Date = Date()) {
        self.localStorage = localStorage
        self.sessionStorage = sessionStorage
        self.cookies = cookies
        self.captureTime = captureTime
    }
    
    public var totalSize: Int {
        let localSize = localStorage.values.joined().utf8.count + localStorage.keys.joined().utf8.count
        let sessionSize = sessionStorage.values.joined().utf8.count + sessionStorage.keys.joined().utf8.count
        let cookieSize = cookies.utf8.count
        return localSize + sessionSize + cookieSize
    }
    
    public var formattedTotalSize: String {
        let bytes = totalSize
        if bytes < 1024 {
            return "\(bytes) B"
        } else if bytes < 1024 * 1024 {
            return String(format: "%.1f KB", Double(bytes) / 1024)
        } else {
            return String(format: "%.1f MB", Double(bytes) / (1024 * 1024))
        }
    }
    
    public var parsedCookies: [[String: String]] {
        return cookies.split(separator: ";").compactMap { cookieString in
            let parts = cookieString.trimmingCharacters(in: .whitespaces).split(separator: "=", maxSplits: 1)
            guard parts.count == 2 else { return nil }
            return [
                "name": String(parts[0]),
                "value": String(parts[1])
            ]
        }
    }
}