import Foundation

public enum ConsoleLogLevel: String, CaseIterable {
    case log = "log"
    case info = "info" 
    case warn = "warn"
    case error = "error"
    case debug = "debug"
    
    public var displayName: String {
        return rawValue.capitalized
    }
    
    public var emoji: String {
        switch self {
        case .log: return "💬"
        case .info: return "ℹ️"
        case .warn: return "⚠️"
        case .error: return "❌"
        case .debug: return "🐛"
        }
    }
}

public struct ConsoleLog {
    public let id = UUID()
    public let level: ConsoleLogLevel
    public let message: String
    public let timestamp: Date
    public let source: String?
    
    public init(level: ConsoleLogLevel, message: String, source: String? = nil) {
        self.level = level
        self.message = message
        self.timestamp = Date()
        self.source = source
    }
    
    public var formattedTimestamp: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SSS"
        return formatter.string(from: timestamp)
    }
    
    public var displayText: String {
        return "\(level.emoji) [\(formattedTimestamp)] \(message)"
    }
}

extension ConsoleLog: Equatable {
    public static func == (lhs: ConsoleLog, rhs: ConsoleLog) -> Bool {
        return lhs.id == rhs.id
    }
}

extension ConsoleLog: Hashable {
    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}