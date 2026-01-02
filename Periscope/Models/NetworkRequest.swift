import Foundation

public enum NetworkRequestStatus {
    case pending
    case success
    case error
}

public struct NetworkRequest {
    public let id: String
    public let url: String
    public let method: String
    public let headers: [String: String]?
    public let requestTime: Date
    public var status: NetworkRequestStatus = .pending
    public var statusCode: Int?
    public var responseHeaders: [String: String]?
    public var responseBody: String?
    public var error: String?
    public var duration: TimeInterval?
    
    public init(id: String, url: String, method: String, headers: [String: String]? = nil, requestTime: Date = Date()) {
        self.id = id
        self.url = url
        self.method = method
        self.headers = headers
        self.requestTime = requestTime
    }
    
    public var formattedDuration: String {
        guard let duration = duration else { return "-" }
        if duration < 1 {
            return String(format: "%.0fms", duration * 1000)
        } else {
            return String(format: "%.2fs", duration)
        }
    }
    
    public var formattedSize: String {
        guard let body = responseBody else { return "-" }
        let bytes = body.utf8.count
        if bytes < 1024 {
            return "\(bytes) B"
        } else if bytes < 1024 * 1024 {
            return String(format: "%.1f KB", Double(bytes) / 1024)
        } else {
            return String(format: "%.1f MB", Double(bytes) / (1024 * 1024))
        }
    }
}