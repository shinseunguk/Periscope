//
//  PeriscopeConfig.swift
//  Periscope
//
//  Created by ukseung.dev on 1/6/26.
//

import Foundation

/// Configuration options for Periscope SDK
public struct PeriscopeConfig {
    /// Enable/disable debug logs from the SDK
    public var debugMode: Bool = false
    
    /// Singleton instance for global configuration
    public static var shared = PeriscopeConfig()
    
    private init() {}
    
    /// Enable debug mode
    public static func enableDebugMode() {
        shared.debugMode = true
    }
    
    /// Disable debug mode
    public static func disableDebugMode() {
        shared.debugMode = false
    }
    
    /// Set debug mode
    public static func setDebugMode(_ enabled: Bool) {
        shared.debugMode = enabled
    }
}

/// Internal logger for Periscope SDK
internal struct PeriscopeLogger {
    static func log(_ message: String, file: String = #file, function: String = #function, line: Int = #line) {
        guard PeriscopeConfig.shared.debugMode else { return }
        let fileName = URL(fileURLWithPath: file).lastPathComponent
        print("🔍 [Periscope] \(fileName):\(line) \(function) - \(message)")
    }
    
    static func error(_ message: String, file: String = #file, function: String = #function, line: Int = #line) {
        guard PeriscopeConfig.shared.debugMode else { return }
        let fileName = URL(fileURLWithPath: file).lastPathComponent
        print("❌ [Periscope] \(fileName):\(line) \(function) - \(message)")
    }
    
    static func warning(_ message: String, file: String = #file, function: String = #function, line: Int = #line) {
        guard PeriscopeConfig.shared.debugMode else { return }
        let fileName = URL(fileURLWithPath: file).lastPathComponent
        print("⚠️ [Periscope] \(fileName):\(line) \(function) - \(message)")
    }
}