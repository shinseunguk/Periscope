//
//  Periscope.swift
//  Periscope
//
//  Created by ukseung.dev on 1/2/26.
//

import Foundation
import UIKit
import WebKit

// This is the main entry point for the Periscope framework
public struct PeriscopeSDK {
    public static let version = "1.0.0"
    
    /// Convenience method to enable Periscope debugging on a WKWebView
    public static func enable(in webView: WKWebView, window: UIWindow? = nil) {
        webView.enablePeriscope()
    }
    
    /// Convenience method to disable Periscope debugging
    public static func disable(in webView: WKWebView) {
        webView.disablePeriscope()
    }
}

