import WebKit
import Foundation

public extension WKWebView {
    
    private struct AssociatedKeys {
        static var isPeriscopeEnabled = "isPeriscopeEnabled"
        static var periscopeMessageHandler = "periscopeMessageHandler"
        static var messageHandlersRegistered = "messageHandlersRegistered"
    }
    
    /// Periscope 디버깅이 활성화되어 있는지 확인
    var isPeriscopeEnabled: Bool {
        get {
            return objc_getAssociatedObject(self, &AssociatedKeys.isPeriscopeEnabled) as? Bool ?? false
        }
        set {
            objc_setAssociatedObject(self, &AssociatedKeys.isPeriscopeEnabled, newValue, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        }
    }
    
    /// Periscope 디버깅 활성화 (자동으로 플로팅 버튼도 함께 활성화)
    /// - Parameter debugger: PeriscopeDebugger 인스턴스 (기본값: shared)
    func enablePeriscope(debugger: PeriscopeDebugger = .shared) {
        print("🔍 enablePeriscope called, current state: \(isPeriscopeEnabled)")
        guard !isPeriscopeEnabled else { 
            print("⚠️ Already enabled, returning")
            return 
        }
        
        // JavaScript 메시지 핸들러 등록 (한 번만 등록)
        let handlersRegistered = objc_getAssociatedObject(self, &AssociatedKeys.messageHandlersRegistered) as? Bool ?? false
        print("🔍 handlersRegistered: \(handlersRegistered)")
        
        // 항상 먼저 제거하고 다시 추가 (중복 방지)
        print("🧹 Removing existing message handlers...")
        configuration.userContentController.removeScriptMessageHandler(forName: "periscopeConsole")
        configuration.userContentController.removeScriptMessageHandler(forName: "periscopeNetwork") 
        configuration.userContentController.removeScriptMessageHandler(forName: "periscopeStorage")
        
        // 새로운 핸들러 등록
        print("📝 Adding new message handlers...")
        let messageHandler = PeriscopeMessageHandler(debugger: debugger)
        objc_setAssociatedObject(self, &AssociatedKeys.periscopeMessageHandler, messageHandler, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        
        configuration.userContentController.add(messageHandler, name: "periscopeConsole")
        configuration.userContentController.add(messageHandler, name: "periscopeNetwork")
        configuration.userContentController.add(messageHandler, name: "periscopeStorage")
        print("✅ Message handlers added")
        
        // Console hook 스크립트 주입
        injectConsoleHookScript()
        
        // 이미 초기화된 경우 활성화만 수행
        let enableScript = """
        (function() {
            if (window.__periscopeInitialized && !window.__periscopeEnabled) {
                window.__periscopeEnabled = true;
                console.log('🟢 Periscope re-enabled');
            }
        })();
        """
        evaluateJavaScript(enableScript, completionHandler: nil)
        
        isPeriscopeEnabled = true
        
        // 자동으로 플로팅 버튼도 활성화
        DispatchQueue.main.async {
            if let window = self.findWindow() {
                debugger.enable(in: window)
            }
        }
    }
    
    /// Periscope 디버깅 비활성화
    func disablePeriscope() {
        guard isPeriscopeEnabled else { return }
        
        // Message handlers 제거
        print("🧹 Removing message handlers on disable...")
        configuration.userContentController.removeScriptMessageHandler(forName: "periscopeConsole")
        configuration.userContentController.removeScriptMessageHandler(forName: "periscopeNetwork")
        configuration.userContentController.removeScriptMessageHandler(forName: "periscopeStorage")
        objc_setAssociatedObject(self, &AssociatedKeys.periscopeMessageHandler, nil, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        
        // Periscope 완전 비활성화 (상태 초기화)
        let disableScript = """
        (function() {
            if (window.__periscopeEnabled) {
                window.__periscopeEnabled = false;
                // 초기화 플래그도 제거하여 다음 enable 시 완전히 새로 시작
                delete window.__periscopeInitialized;
                console.log('🔴 Periscope disabled and reset');
            }
        })();
        """
        
        evaluateJavaScript(disableScript, completionHandler: nil)
        
        // UserScripts 모두 제거 (다음 enable 시 깨끗하게 시작)
        print("🧹 Removing all user scripts...")
        configuration.userContentController.removeAllUserScripts()
        
        // 플로팅 버튼도 함께 비활성화
        PeriscopeDebugger.shared.disable()
        
        isPeriscopeEnabled = false
    }
    
    /// WKWebView가 속한 윈도우를 찾는 헬퍼 메서드
    private func findWindow() -> UIWindow? {
        var responder: UIResponder? = self
        while let nextResponder = responder?.next {
            if let window = nextResponder as? UIWindow {
                return window
            }
            responder = nextResponder
        }
        
        // Fallback: 현재 key window 사용
        if #available(iOS 13.0, *) {
            return UIApplication.shared.connectedScenes
                .compactMap { $0 as? UIWindowScene }
                .flatMap { $0.windows }
                .first { $0.isKeyWindow }
        } else {
            return UIApplication.shared.keyWindow
        }
    }
    
    /// Console hook JavaScript 스크립트 주입
    private func injectConsoleHookScript() {
        // 이미 userScript가 추가되어 있는지 확인
        let hasUserScript = !configuration.userContentController.userScripts.isEmpty
        print("🔍 injectConsoleHookScript - hasUserScript: \(hasUserScript), userScripts count: \(configuration.userContentController.userScripts.count)")
        
        // SPM의 경우 Bundle.module 사용
        #if SWIFT_PACKAGE
        guard let scriptURL = Bundle.module.url(forResource: "ConsoleHook", withExtension: "js"),
              let scriptContent = try? String(contentsOf: scriptURL) else {
            // 파일을 찾을 수 없으면 인라인 스크립트 사용
            injectInlineConsoleHookScript()
            return
        }
        #else
        guard let scriptPath = Bundle.main.path(forResource: "ConsoleHook", ofType: "js"),
              let scriptContent = try? String(contentsOfFile: scriptPath) else {
            
            // Bundle에서 찾을 수 없으면 SDK Bundle에서 찾기
            guard let periscopeBundle = getPeriscopeBundle(),
                  let scriptPath = periscopeBundle.path(forResource: "ConsoleHook", ofType: "js"),
                  let scriptContent = try? String(contentsOfFile: scriptPath) else {
                
                // 파일을 찾을 수 없으면 인라인 스크립트 사용
                injectInlineConsoleHookScript()
                return
            }
            
            // UserScript가 없을 때만 추가
            if !hasUserScript {
                let userScript = WKUserScript(source: scriptContent, injectionTime: .atDocumentStart, forMainFrameOnly: false)
                configuration.userContentController.addUserScript(userScript)
            }
            
            // 이미 로드된 페이지에서도 스크립트가 실행되도록 강제 주입
            // 중복 실행 방지를 위해 체크 후 실행
            evaluateJavaScript("typeof window.__periscopeInitialized === 'undefined'") { [weak self] result, error in
                if let isNotInitialized = result as? Bool, isNotInitialized {
                    self?.evaluateJavaScript(scriptContent, completionHandler: nil)
                }
            }
            
            return
        }
        #endif
        
        // UserScript가 없을 때만 추가
        if !hasUserScript {
            let userScript = WKUserScript(source: scriptContent, injectionTime: .atDocumentStart, forMainFrameOnly: false)
            configuration.userContentController.addUserScript(userScript)
        }
        
        // 페이지가 이미 로드되어 있고, 스크립트가 아직 초기화되지 않은 경우에만 실행
        evaluateJavaScript("document.readyState") { [weak self] result, error in
            if let readyState = result as? String, readyState != "loading" {
                // 페이지가 로드된 상태에서 스크립트 초기화 여부 확인
                self?.evaluateJavaScript("typeof window.__periscopeInitialized === 'undefined'") { result, error in
                    if let isNotInitialized = result as? Bool, isNotInitialized {
                        print("🔧 Injecting script via evaluateJavaScript (page already loaded)")
                        self?.evaluateJavaScript(scriptContent, completionHandler: nil)
                    } else {
                        print("ℹ️ Script already initialized, skipping evaluateJavaScript")
                    }
                }
            } else {
                print("ℹ️ Page is still loading, UserScript will handle initialization")
            }
        }
    }
    
    /// Periscope Bundle 가져오기
    private func getPeriscopeBundle() -> Bundle? {
        // SPM의 경우
        if let bundlePath = Bundle.main.path(forResource: "Periscope_Periscope", ofType: "bundle"),
           let bundle = Bundle(path: bundlePath) {
            return bundle
        }
        
        // CocoaPods의 경우
        if let bundlePath = Bundle.main.path(forResource: "Periscope", ofType: "bundle"),
           let bundle = Bundle(path: bundlePath) {
            return bundle
        }
        
        // 현재 Bundle에서 찾기
        return Bundle(for: PeriscopeDebugger.self)
    }
    
    /// 인라인 Console Hook 스크립트 주입 (fallback)
    private func injectInlineConsoleHookScript() {
        // 이미 userScript가 추가되어 있는지 확인
        let hasUserScript = !configuration.userContentController.userScripts.isEmpty
        
        let inlineScript = """
        (function() {
            'use strict';
            
            // 중복 실행 방지
            if (window.__periscopeInitialized) {
                console.log('⚠️ Periscope script already initialized, skipping...');
                // 활성화 상태만 업데이트
                window.__periscopeEnabled = true;
                console.log('🟢 Periscope re-enabled (script already initialized)');
                return;
            }
            window.__periscopeInitialized = true;
            console.log('🚀 Periscope script initializing for the first time...');
            
            // Periscope 활성화 상태 관리
            window.__periscopeEnabled = true;
            
            const originalConsole = {
                log: console.log,
                info: console.info,
                warn: console.warn,
                error: console.error,
                debug: console.debug
            };
            
            // 원본 console을 전역에서 접근 가능하도록 노출
            window.originalConsole = originalConsole;
            
            function sendToNative(level, args) {
                // Periscope가 비활성화되어 있으면 전송하지 않음
                if (!window.__periscopeEnabled) {
                    return;
                }
                
                try {
                    const message = args.map(arg => {
                        if (typeof arg === 'object') {
                            try {
                                return JSON.stringify(arg, null, 2);
                            } catch (e) {
                                return '[Circular Object]';
                            }
                        } else {
                            return String(arg);
                        }
                    }).join(' ');
                    
                    let source = null;
                    try {
                        const stack = new Error().stack;
                        const lines = stack.split('\\n');
                        for (let i = 2; i < lines.length; i++) {
                            const line = lines[i].trim();
                            if (!line.includes('webkit-masked-url')) {
                                source = line;
                                break;
                            }
                        }
                    } catch (e) {}
                    
                    if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.periscopeConsole) {
                        window.webkit.messageHandlers.periscopeConsole.postMessage({
                            level: level,
                            message: message,
                            source: source,
                            timestamp: new Date().getTime()
                        });
                    }
                } catch (e) {
                    originalConsole.error('Periscope console hook error:', e);
                }
            }
            
            console.log = function() {
                originalConsole.log.apply(console, arguments);
                sendToNative('log', Array.from(arguments));
            };
            
            console.info = function() {
                originalConsole.info.apply(console, arguments);
                sendToNative('info', Array.from(arguments));
            };
            
            console.warn = function() {
                originalConsole.warn.apply(console, arguments);
                sendToNative('warn', Array.from(arguments));
            };
            
            console.error = function() {
                originalConsole.error.apply(console, arguments);
                sendToNative('error', Array.from(arguments));
            };
            
            console.debug = function() {
                originalConsole.debug.apply(console, arguments);
                sendToNative('debug', Array.from(arguments));
            };
            
            window.addEventListener('error', function(event) {
                // Script error from cross-origin scripts 무시
                if (event.message === 'Script error.' && event.filename === '') {
                    return;
                }
                
                const errorMsg = `Uncaught Error: ${event.message || 'Unknown error'}`;
                const location = `at ${event.filename || 'unknown'}:${event.lineno || 0}:${event.colno || 0}`;
                const stackInfo = event.error && event.error.stack ? `Stack: ${event.error.stack}` : 'No stack trace';
                sendToNative('error', [errorMsg, location, stackInfo]);
            });
            
            window.addEventListener('unhandledrejection', function(event) {
                const reason = event.reason ? JSON.stringify(event.reason) : 'Unknown reason';
                sendToNative('error', [`Unhandled Promise Rejection: ${reason}`]);
            });
            
            sendToNative('info', ['Periscope console hook initialized']);
            
            // Network monitoring
            const originalFetch = window.fetch;
            window.__originalFetch = originalFetch; // 원본 fetch 저장 (복원용)
            
            window.fetch = function(...args) {
                const [url, options = {}] = args;
                const startTime = Date.now();
                const requestId = Math.random().toString(36).substr(2, 9);
                
                // Periscope가 비활성화되어 있으면 원본 fetch만 호출
                if (!window.__periscopeEnabled) {
                    return originalFetch.apply(this, args);
                }
                
                if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.periscopeNetwork) {
                    window.webkit.messageHandlers.periscopeNetwork.postMessage({
                        type: 'request',
                        id: requestId,
                        url: url.toString(),
                        method: options.method || 'GET',
                        headers: options.headers || {},
                        timestamp: startTime
                    });
                } else {
                    console.warn('⚠️ Periscope: Network message handler not available');
                }
                
                return originalFetch.apply(this, args).then(response => {
                    if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.periscopeNetwork) {
                        // Collect response headers
                        const responseHeaders = {};
                        for (const [key, value] of response.headers.entries()) {
                            responseHeaders[key] = value;
                        }
                        
                        // Content-Type에 따라 응답 바디 처리
                        const contentType = response.headers.get('content-type') || '';
                        const responseClone = response.clone();
                        
                        function sendResponseData(bodyData) {
                            window.webkit.messageHandlers.periscopeNetwork.postMessage({
                                type: 'response',
                                id: requestId,
                                status: response.status,
                                statusText: response.statusText,
                                headers: responseHeaders,
                                body: bodyData,
                                duration: Date.now() - startTime,
                                timestamp: Date.now()
                            });
                        }
                        
                        if (contentType.includes('application/json')) {
                            // JSON 응답
                            responseClone.json().then(data => {
                                sendResponseData(JSON.stringify(data, null, 2).substr(0, 5000));
                            }).catch(() => {
                                responseClone.text().then(text => {
                                    sendResponseData(text.substr(0, 5000));
                                }).catch(() => {
                                    sendResponseData('[Unable to read response body]');
                                });
                            });
                        } else if (contentType.includes('text/') || contentType.includes('application/xml')) {
                            // 텍스트 응답
                            responseClone.text().then(text => {
                                sendResponseData(text.substr(0, 5000));
                            }).catch(() => {
                                sendResponseData('[Unable to read response body]');
                            });
                        } else {
                            // 바이너리 또는 기타 응답
                            responseClone.arrayBuffer().then(buffer => {
                                sendResponseData('[Binary data: ' + buffer.byteLength + ' bytes]');
                            }).catch(() => {
                                sendResponseData('[Unable to read response body]');
                            });
                        }
                    }
                    return response;
                }).catch(error => {
                    if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.periscopeNetwork) {
                        window.webkit.messageHandlers.periscopeNetwork.postMessage({
                            type: 'error',
                            id: requestId,
                            error: error.message,
                            duration: Date.now() - startTime
                        });
                    }
                    throw error;
                });
            };
            
            // Storage monitoring
            function captureStorageData() {
                try {
                    originalConsole.log('🔍 captureStorageData called');
                    const storageData = { localStorage: {}, sessionStorage: {}, cookies: document.cookie };
                    
                    originalConsole.log('📊 localStorage length:', localStorage.length);
                    for (let i = 0; i < localStorage.length; i++) {
                        const key = localStorage.key(i);
                        storageData.localStorage[key] = localStorage.getItem(key);
                    }
                    
                    originalConsole.log('📊 sessionStorage length:', sessionStorage.length);
                    for (let i = 0; i < sessionStorage.length; i++) {
                        const key = sessionStorage.key(i);
                        storageData.sessionStorage[key] = sessionStorage.getItem(key);
                    }
                    
                    originalConsole.log('🗃️ Capturing storage data:', JSON.stringify(storageData, null, 2));
                    
                    if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.periscopeStorage) {
                        originalConsole.log('✅ periscopeStorage handler found, posting message...');
                        window.webkit.messageHandlers.periscopeStorage.postMessage(storageData);
                        originalConsole.log('📤 Storage data sent to native');
                    } else {
                        originalConsole.warn('⚠️ Periscope: Storage message handler not available');
                        originalConsole.log('webkit:', window.webkit);
                        originalConsole.log('messageHandlers:', window.webkit && window.webkit.messageHandlers);
                        originalConsole.log('periscopeStorage:', window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.periscopeStorage);
                    }
                } catch (e) {
                    originalConsole.error('❌ Storage capture error:', e);
                }
            }
            
            // 전역에서 접근 가능하도록 노출
            window.captureStorageData = captureStorageData;
            originalConsole.log('✅ window.captureStorageData has been set');
            
            // Storage event monitoring - Hook setItem, removeItem, clear
            const originalSetItem = Storage.prototype.setItem;
            const originalRemoveItem = Storage.prototype.removeItem;
            const originalClear = Storage.prototype.clear;
            
            // 원본 함수들을 전역에 저장 (나중에 복원용)
            window.__originalSetItem = originalSetItem;
            window.__originalRemoveItem = originalRemoveItem;
            window.__originalClear = originalClear;
            
            Storage.prototype.setItem = function(key, value) {
                try {
                    originalSetItem.apply(this, arguments);
                    
                    // Periscope가 활성화되어 있을 때만 캡처
                    if (window.__periscopeEnabled) {
                        originalConsole.log('🔧 Storage setItem called:', key, value);
                        originalConsole.log('⏰ Scheduling captureStorageData...');
                        setTimeout(function() {
                            originalConsole.log('📤 Calling captureStorageData from setItem');
                            captureStorageData();
                        }, 100);
                    }
                } catch (e) {
                    originalConsole.error('Storage setItem error:', e);
                }
            };
            
            Storage.prototype.removeItem = function(key) {
                try {
                    originalRemoveItem.apply(this, arguments);
                    setTimeout(captureStorageData, 10);
                } catch (e) {
                    originalConsole.error('Storage removeItem error:', e);
                }
            };
            
            Storage.prototype.clear = function() {
                try {
                    originalClear.apply(this, arguments);
                    setTimeout(captureStorageData, 10);
                } catch (e) {
                    originalConsole.error('Storage clear error:', e);
                }
            };
            
            // 초기 Storage 데이터 캡처를 좀 더 늦게 실행
            setTimeout(function() {
                originalConsole.log('📱 Initial storage capture after 500ms');
                if (window.captureStorageData) {
                    originalConsole.log('✅ captureStorageData is available, calling it...');
                    captureStorageData();
                } else {
                    originalConsole.error('❌ captureStorageData is NOT available at initial capture time');
                }
            }, 500);
            
            // 스크립트 초기화 완료 확인
            originalConsole.log('🎉 Storage monitoring script initialization completed');
            originalConsole.log('📌 window.captureStorageData available:', typeof window.captureStorageData === 'function');
        })();
        """
        
        // UserScript가 없을 때만 추가
        if !hasUserScript {
            let userScript = WKUserScript(source: inlineScript, injectionTime: .atDocumentStart, forMainFrameOnly: false)
            configuration.userContentController.addUserScript(userScript)
        }
        
        // 페이지가 이미 로드되어 있고, 스크립트가 아직 초기화되지 않은 경우에만 실행
        evaluateJavaScript("document.readyState") { [weak self] result, error in
            if let readyState = result as? String, readyState != "loading" {
                // 페이지가 로드된 상태에서 스크립트 초기화 여부 확인
                self?.evaluateJavaScript("typeof window.__periscopeInitialized === 'undefined'") { result, error in
                    if let isNotInitialized = result as? Bool, isNotInitialized {
                        print("🔧 Injecting inline script via evaluateJavaScript (page already loaded)")
                        self?.evaluateJavaScript(inlineScript, completionHandler: nil)
                    } else {
                        print("ℹ️ Script already initialized, skipping evaluateJavaScript")
                    }
                }
            } else {
                print("ℹ️ Page is still loading, UserScript will handle initialization")
            }
        }
    }
}

// MARK: - PeriscopeMessageHandler

private class PeriscopeMessageHandler: NSObject, WKScriptMessageHandler {
    
    private weak var debugger: PeriscopeDebugger?
    
    init(debugger: PeriscopeDebugger) {
        self.debugger = debugger
        super.init()
    }
    
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let debugger = debugger else { return }
        
        switch message.name {
        case "periscopeConsole":
            handleConsoleMessage(message, debugger: debugger)
        case "periscopeNetwork":
            handleNetworkMessage(message, debugger: debugger)
        case "periscopeStorage":
            handleStorageMessage(message, debugger: debugger)
        default:
            break
        }
    }
    
    private func handleConsoleMessage(_ message: WKScriptMessage, debugger: PeriscopeDebugger) {
        guard let body = message.body as? [String: Any],
              let levelString = body["level"] as? String,
              let messageText = body["message"] as? String,
              let level = ConsoleLogLevel(rawValue: levelString) else {
            return
        }
        
        // 네트워크 응답 로그인지 확인 (더 구체적인 키워드)
        let networkResponseKeywords = ["fetch success", "fetch error", "post success", "post error", "get success", "get error", "mock api success", "mock api error"]
        let isNetworkResponseLog = networkResponseKeywords.contains { keyword in
            messageText.lowercased().contains(keyword.lowercased())
        }
        
        if isNetworkResponseLog {
            // 네트워크 응답 로그는 Console 탭에 표시하지 않음 (Network 탭에서 확인 가능)
            print("📝 Network response log filtered from Console tab: \(messageText.prefix(50))...")
            return
        }
        
        let source = body["source"] as? String
        let log = ConsoleLog(level: level, message: messageText, source: source)
        
        debugger.addLog(log)
    }
    
    private func handleNetworkMessage(_ message: WKScriptMessage, debugger: PeriscopeDebugger) {
        guard let body = message.body as? [String: Any],
              let type = body["type"] as? String,
              let id = body["id"] as? String else { 
            print("❌ Network message parsing failed: \(message.body)")
            return 
        }
        
        print("📡 Network message received: \(type) for \(id)")
        
        switch type {
        case "request":
            let request = NetworkRequest(
                id: id,
                url: body["url"] as? String ?? "",
                method: body["method"] as? String ?? "GET",
                headers: body["headers"] as? [String: String]
            )
            debugger.addNetworkRequest(request)
            print("✅ Network request added: \(request.method) \(request.url)")
            
        case "response":
            debugger.updateNetworkRequest(id: id, response: body)
            print("✅ Network response updated for \(id)")
            
        case "error":
            debugger.updateNetworkRequestError(
                id: id,
                error: body["error"] as? String ?? "Unknown error",
                duration: body["duration"] as? Double
            )
            print("❌ Network error updated for \(id)")
            
        default:
            print("⚠️ Unknown network message type: \(type)")
            break
        }
    }
    
    private func handleStorageMessage(_ message: WKScriptMessage, debugger: PeriscopeDebugger) {
        print("💾 Storage message received: \(message.body)")
        guard let body = message.body as? [String: Any] else { 
            print("❌ Storage message body parsing failed")
            return 
        }
        
        let localStorage = body["localStorage"] as? [String: String] ?? [:]
        let sessionStorage = body["sessionStorage"] as? [String: String] ?? [:]
        let cookies = body["cookies"] as? String ?? ""
        
        print("📦 Parsed storage data:")
        print("  - localStorage: \(localStorage.count) items: \(localStorage)")
        print("  - sessionStorage: \(sessionStorage.count) items: \(sessionStorage)")
        print("  - cookies: \(cookies.isEmpty ? "empty" : cookies)")
        
        let storageData = StorageData(
            localStorage: localStorage,
            sessionStorage: sessionStorage,
            cookies: cookies
        )
        
        debugger.updateStorageData(storageData)
    }
}

// MARK: - Convenience Methods

public extension WKWebView {
    
    /// 테스트용 HTML 로드 (console.log 테스트용)
    func loadTestHTML() {
        let html = """
        <!DOCTYPE html>
        <html>
        <head>
            <title>Periscope Test</title>
            <meta charset="utf-8">
            <meta name="viewport" content="width=device-width, initial-scale=1.0">
            <style>
                body {
                    font-family: -apple-system, BlinkMacSystemFont, sans-serif;
                    padding: 20px;
                    background-color: #f5f5f5;
                }
                .button {
                    background-color: #007AFF;
                    color: white;
                    border: none;
                    padding: 12px 24px;
                    border-radius: 8px;
                    font-size: 16px;
                    margin: 8px;
                    cursor: pointer;
                }
                .button:hover {
                    background-color: #0056CC;
                }
                .container {
                    max-width: 600px;
                    margin: 0 auto;
                    background: white;
                    border-radius: 12px;
                    padding: 20px;
                    box-shadow: 0 2px 10px rgba(0,0,0,0.1);
                }
                h1 {
                    color: #333;
                    margin-bottom: 20px;
                }
                .section {
                    margin-bottom: 20px;
                }
            </style>
        </head>
        <body>
            <div class="container">
                <h1>🔍 Periscope Console Test</h1>
                
                <div class="section">
                    <h3>Basic Console Methods</h3>
                    <button class="button" onclick="testLog()">console.log()</button>
                    <button class="button" onclick="testInfo()">console.info()</button>
                    <button class="button" onclick="testWarn()">console.warn()</button>
                    <button class="button" onclick="testError()">console.error()</button>
                    <button class="button" onclick="testDebug()">console.debug()</button>
                </div>
                
                <div class="section">
                    <h3>Advanced Tests</h3>
                    <button class="button" onclick="testObject()">Log Object</button>
                    <button class="button" onclick="testArray()">Log Array</button>
                    <button class="button" onclick="testMultipleArgs()">Multiple Args</button>
                </div>
                
                <div class="section">
                    <h3>Error Tests</h3>
                    <button class="button" onclick="testException()">Throw Error</button>
                    <button class="button" onclick="testPromiseRejection()">Promise Rejection</button>
                </div>
                
                <div class="section">
                    <h3>Stress Test</h3>
                    <button class="button" onclick="stressTest()">100 Logs</button>
                    <button class="button" onclick="clearConsole()">Clear Console</button>
                </div>
                
                <div class="section">
                    <h3>Network Tests</h3>
                    <button class="button" onclick="testFetch()">Test JSON</button>
                    <button class="button" onclick="test404()">Test 404</button>
                    <button class="button" onclick="testPost()">Test POST</button>
                    <button class="button" onclick="testMockAPI()">Test Mock API</button>
                </div>
                
                <div class="section">
                    <h3>Storage Tests</h3>
                    <button class="button" onclick="testLocalStorage()">Set LocalStorage</button>
                    <button class="button" onclick="testSessionStorage()">Set SessionStorage</button>
                    <button class="button" onclick="testCookies()">Set Cookie</button>
                </div>
            </div>
            
            <script>
                function testLog() {
                    console.log('This is a regular log message');
                }
                
                function testInfo() {
                    console.info('This is an info message with some details');
                }
                
                function testWarn() {
                    console.warn('This is a warning message - something might be wrong');
                }
                
                function testError() {
                    console.error('This is an error message - something went wrong!');
                }
                
                function testDebug() {
                    console.debug('This is a debug message for developers');
                }
                
                function testObject() {
                    const obj = {
                        name: 'John Doe',
                        age: 30,
                        city: 'New York',
                        hobbies: ['reading', 'coding', 'gaming'],
                        address: {
                            street: '123 Main St',
                            zipCode: '10001'
                        }
                    };
                    console.log('User object:', obj);
                }
                
                function testArray() {
                    const arr = [1, 2, 3, 'hello', true, { key: 'value' }];
                    console.log('Mixed array:', arr);
                }
                
                function testMultipleArgs() {
                    console.log('Multiple', 'arguments:', 123, true, { test: 'object' });
                }
                
                function testException() {
                    throw new Error('This is a test exception!');
                }
                
                function testPromiseRejection() {
                    Promise.reject('This is a test promise rejection');
                }
                
                function stressTest() {
                    for (let i = 1; i <= 100; i++) {
                        console.log(`Stress test message #${i}`);
                    }
                }
                
                function clearConsole() {
                    // This would clear the browser console, but Periscope will still show its logs
                    console.clear();
                    console.log('Browser console cleared (Periscope logs remain)');
                }
                
                // Initial message
                console.log('🚀 Periscope test page loaded successfully!');
                console.info('ℹ️ Click the buttons above to test different console methods');
                
                // Debug: Check if captureStorageData is available
                setTimeout(function() {
                    console.log('🔍 Checking captureStorageData availability after page load...');
                    console.log('  - window.captureStorageData:', typeof window.captureStorageData);
                    console.log('  - window.__periscopeInitialized:', window.__periscopeInitialized);
                }, 1000);
                
                // Fallback: Define captureStorageData if not available
                if (!window.captureStorageData) {
                    console.log('⚠️ captureStorageData not found, defining fallback...');
                    window.captureStorageData = function() {
                        try {
                            console.log('📦 Fallback captureStorageData called');
                            const storageData = { localStorage: {}, sessionStorage: {}, cookies: document.cookie };
                            
                            // Capture localStorage
                            for (let i = 0; i < localStorage.length; i++) {
                                const key = localStorage.key(i);
                                storageData.localStorage[key] = localStorage.getItem(key);
                            }
                            
                            // Capture sessionStorage
                            for (let i = 0; i < sessionStorage.length; i++) {
                                const key = sessionStorage.key(i);
                                storageData.sessionStorage[key] = sessionStorage.getItem(key);
                            }
                            
                            console.log('📦 Storage data captured:', JSON.stringify(storageData, null, 2));
                            
                            // Send to native
                            if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.periscopeStorage) {
                                window.webkit.messageHandlers.periscopeStorage.postMessage(storageData);
                                console.log('✅ Storage data sent to native via fallback');
                            } else {
                                console.error('❌ periscopeStorage message handler not available');
                            }
                        } catch (e) {
                            console.error('❌ Fallback captureStorageData error:', e);
                        }
                    };
                    console.log('✅ Fallback captureStorageData defined');
                }
                
                // Test functions for console execution
                window.test = function() {
                    console.log('Hello from window.test()!');
                    return 'Test function executed successfully';
                };
                
                window.calculate = function(a, b) {
                    const result = a + b;
                    console.log(`Calculating: ${a} + ${b} = ${result}`);
                    return result;
                };
                
                window.getInfo = function() {
                    return {
                        title: document.title,
                        url: window.location.href,
                        userAgent: navigator.userAgent.substring(0, 50) + '...',
                        timestamp: new Date().toISOString()
                    };
                };
                
                window.randomNumber = function(min = 1, max = 100) {
                    const num = Math.floor(Math.random() * (max - min + 1)) + min;
                    console.log(`Generated random number: ${num}`);
                    return num;
                };
                
                // Storage 테스트를 위한 전역 함수들
                window.testStorage = function() {
                    console.log('Testing storage functions...');
                    localStorage.setItem('debug-test', 'LocalStorage test value');
                    sessionStorage.setItem('debug-session', 'SessionStorage test value');
                    document.cookie = 'debug-cookie=CookieTestValue; path=/';
                    console.log('Storage items set. Check Storage tab.');
                    
                    // 수동으로 storage 데이터 전송
                    setTimeout(function() {
                        console.log('Manually triggering storage data capture...');
                        if (window.captureStorageData) {
                            window.captureStorageData();
                        } else {
                            console.error('captureStorageData function not found');
                        }
                    }, 100);
                    
                    return 'Storage test completed';
                };
                
                window.clearStorage = function() {
                    console.log('Clearing all storage...');
                    localStorage.clear();
                    sessionStorage.clear();
                    // 쿠키 삭제는 복잡하므로 생략
                    console.log('Storage cleared. Check Storage tab.');
                    
                    // 수동으로 storage 데이터 전송
                    setTimeout(function() {
                        console.log('Manually triggering storage data capture after clear...');
                        if (window.captureStorageData) {
                            window.captureStorageData();
                        }
                    }, 100);
                    
                    return 'Storage cleared';
                };
                
                window.delay = function(ms = 1000) {
                    console.log(`Starting ${ms}ms delay...`);
                    return new Promise(resolve => {
                        setTimeout(() => {
                            console.log('Delay completed!');
                            resolve(`Waited ${ms}ms`);
                        }, ms);
                    });
                };
                
                // Network test functions - 전역 함수로 만들기
                window.testFetch = function() {
                    console.log('Testing JSON fetch...');
                    return fetch('https://jsonplaceholder.typicode.com/posts/1')
                        .then(response => {
                            console.log('Response status:', response.status);
                            console.log('Response headers:', Object.fromEntries(response.headers.entries()));
                            return response.json();
                        })
                        .then(data => {
                            console.log('Fetch success:', JSON.stringify(data, null, 2));
                            return data;
                        })
                        .catch(error => {
                            console.error('Fetch error:', error);
                            throw error;
                        });
                };
                
                window.test404 = function() {
                    console.log('Testing 404 error...');
                    return fetch('https://jsonplaceholder.typicode.com/posts/99999')
                        .then(response => {
                            console.log('Response status:', response.status);
                            console.log('Response ok:', response.ok);
                            if (!response.ok) {
                                throw new Error(`HTTP ${response.status}: ${response.statusText}`);
                            }
                            return response.json();
                        })
                        .catch(error => {
                            console.error('Expected 404 error:', error.message);
                            return { error: error.message };
                        });
                };
                
                window.testPost = function() {
                    console.log('Testing POST request...');
                    const postData = {
                        title: 'Test Post from Console',
                        body: 'This is a test post created from Periscope console',
                        userId: 1
                    };
                    console.log('POST data:', JSON.stringify(postData, null, 2));
                    
                    return fetch('https://jsonplaceholder.typicode.com/posts', {
                        method: 'POST',
                        headers: {
                            'Content-Type': 'application/json',
                        },
                        body: JSON.stringify(postData)
                    })
                    .then(response => {
                        console.log('POST response status:', response.status);
                        return response.json();
                    })
                    .then(data => {
                        console.log('POST success:', JSON.stringify(data, null, 2));
                        return data;
                    })
                    .catch(error => {
                        console.error('POST error:', error);
                        throw error;
                    });
                };
                
                // Storage test functions
                function testLocalStorage() {
                    console.log('🔵 === Starting LocalStorage Test ===');
                    
                    try {
                        // Check if localStorage is available
                        if (typeof localStorage === 'undefined') {
                            console.error('❌ localStorage is undefined');
                            return;
                        }
                        
                        console.log('✅ localStorage is available');
                        console.log('📝 typeof localStorage:', typeof localStorage);
                        
                        // Try to access length safely
                        let lengthBefore = 0;
                        try {
                            lengthBefore = localStorage.length || 0;
                            console.log('📝 Current localStorage length before:', lengthBefore);
                        } catch (e) {
                            console.error('❌ Error accessing localStorage.length:', e);
                        }
                        
                        // First item
                        const testKey = 'test-key';
                        const testValue = 'Test value at ' + new Date().toLocaleTimeString();
                        console.log(`📝 Setting localStorage['${testKey}'] = '${testValue}'`);
                        
                        try {
                            localStorage.setItem(testKey, testValue);
                            console.log('✅ First item set successfully');
                        } catch (e) {
                            console.error('❌ Error setting first item:', e);
                        }
                        
                        // Second item
                        const userData = {name: 'John', age: 30};
                        const userDataStr = JSON.stringify(userData);
                        console.log(`📝 Setting localStorage['user'] = '${userDataStr}'`);
                        
                        try {
                            localStorage.setItem('user', userDataStr);
                            console.log('✅ Second item set successfully');
                        } catch (e) {
                            console.error('❌ Error setting second item:', e);
                        }
                        
                        // Try to access length after
                        let lengthAfter = 0;
                        try {
                            lengthAfter = localStorage.length || 0;
                            console.log('📝 Current localStorage length after:', lengthAfter);
                        } catch (e) {
                            console.error('❌ Error accessing localStorage.length after:', e);
                        }
                        
                        // List all keys
                        console.log('📝 Trying to list all localStorage keys...');
                        try {
                            for (let i = 0; i < lengthAfter; i++) {
                                const key = localStorage.key(i);
                                const value = localStorage.getItem(key);
                                console.log(`  - ${key}: ${value}`);
                            }
                        } catch (e) {
                            console.error('❌ Error listing keys:', e);
                        }
                        
                        console.log('✅ LocalStorage test completed');
                        
                        // Manual trigger for debugging
                        console.log('🔍 Checking for window.captureStorageData...');
                        console.log('  - typeof window:', typeof window);
                        console.log('  - typeof window.captureStorageData:', typeof window.captureStorageData);
                        console.log('  - window.captureStorageData:', window.captureStorageData);
                        
                        if (window.captureStorageData && typeof window.captureStorageData === 'function') {
                            console.log('🔄 Manually calling captureStorageData...');
                            window.captureStorageData();
                        } else {
                            console.error('❌ window.captureStorageData not found!');
                            console.log('🔍 Checking window properties:');
                            const keys = Object.keys(window).filter(key => key.includes('capture') || key.includes('Storage'));
                            console.log('  - Related keys:', keys);
                        }
                        
                    } catch (error) {
                        console.error('❌ LocalStorage test error:', error);
                        console.error('Error type:', typeof error);
                        console.error('Error message:', error.message || 'No message');
                        console.error('Error stack:', error.stack || 'No stack');
                    }
                    
                    console.log('🔵 === End LocalStorage Test ===');
                }
                
                function testSessionStorage() {
                    console.log('🟢 === Starting SessionStorage Test ===');
                    
                    try {
                        // Check if sessionStorage is available
                        if (typeof sessionStorage === 'undefined') {
                            console.error('❌ sessionStorage is undefined');
                            return;
                        }
                        
                        console.log('✅ sessionStorage is available');
                        console.log('📝 typeof sessionStorage:', typeof sessionStorage);
                        
                        // Try to access length safely
                        let lengthBefore = 0;
                        try {
                            lengthBefore = sessionStorage.length || 0;
                            console.log('📝 Current sessionStorage length before:', lengthBefore);
                        } catch (e) {
                            console.error('❌ Error accessing sessionStorage.length:', e);
                        }
                        
                        // First item
                        const sessionKey = 'session-key';
                        const sessionValue = 'Session value at ' + new Date().toLocaleTimeString();
                        console.log(`📝 Setting sessionStorage['${sessionKey}'] = '${sessionValue}'`);
                        
                        try {
                            sessionStorage.setItem(sessionKey, sessionValue);
                            console.log('✅ First item set successfully');
                        } catch (e) {
                            console.error('❌ Error setting first item:', e);
                        }
                        
                        // Second item
                        const tempData = 'This will be cleared when browser closes';
                        console.log(`📝 Setting sessionStorage['temp-data'] = '${tempData}'`);
                        
                        try {
                            sessionStorage.setItem('temp-data', tempData);
                            console.log('✅ Second item set successfully');
                        } catch (e) {
                            console.error('❌ Error setting second item:', e);
                        }
                        
                        // Try to access length after
                        let lengthAfter = 0;
                        try {
                            lengthAfter = sessionStorage.length || 0;
                            console.log('📝 Current sessionStorage length after:', lengthAfter);
                        } catch (e) {
                            console.error('❌ Error accessing sessionStorage.length after:', e);
                        }
                        
                        // List all keys
                        console.log('📝 Trying to list all sessionStorage keys...');
                        try {
                            for (let i = 0; i < lengthAfter; i++) {
                                const key = sessionStorage.key(i);
                                const value = sessionStorage.getItem(key);
                                console.log(`  - ${key}: ${value}`);
                            }
                        } catch (e) {
                            console.error('❌ Error listing keys:', e);
                        }
                        
                        console.log('✅ SessionStorage test completed');
                        
                        // Manual trigger for debugging
                        console.log('🔍 Checking for window.captureStorageData...');
                        console.log('  - typeof window:', typeof window);
                        console.log('  - typeof window.captureStorageData:', typeof window.captureStorageData);
                        console.log('  - window.captureStorageData:', window.captureStorageData);
                        
                        if (window.captureStorageData && typeof window.captureStorageData === 'function') {
                            console.log('🔄 Manually calling captureStorageData...');
                            window.captureStorageData();
                        } else {
                            console.error('❌ window.captureStorageData not found!');
                            console.log('🔍 Checking window properties:');
                            const keys = Object.keys(window).filter(key => key.includes('capture') || key.includes('Storage'));
                            console.log('  - Related keys:', keys);
                        }
                        
                    } catch (error) {
                        console.error('❌ SessionStorage test error:', error);
                        console.error('Error type:', typeof error);
                        console.error('Error message:', error.message || 'No message');
                        console.error('Error stack:', error.stack || 'No stack');
                    }
                    
                    console.log('🟢 === End SessionStorage Test ===');
                }
                
                function testCookies() {
                    console.log('🟡 === Starting Cookie Test ===');
                    
                    try {
                        console.log('📝 Current cookies before:', document.cookie);
                        
                        // First cookie
                        const cookie1 = 'test-cookie=value123; path=/';
                        console.log(`📝 Setting cookie: '${cookie1}'`);
                        document.cookie = cookie1;
                        console.log('✅ First cookie set successfully');
                        
                        // Second cookie with expiry
                        const expiryDate = new Date(Date.now() + 86400000).toUTCString();
                        const cookie2 = `user-preference=dark-mode; expires=${expiryDate}`;
                        console.log(`📝 Setting cookie: '${cookie2}'`);
                        document.cookie = cookie2;
                        console.log('✅ Second cookie set successfully');
                        
                        console.log('📝 Current cookies after:', document.cookie);
                        console.log('✅ Cookies updated successfully');
                        
                        // Manual trigger for debugging
                        console.log('🔍 Checking for window.captureStorageData...');
                        console.log('  - typeof window:', typeof window);
                        console.log('  - typeof window.captureStorageData:', typeof window.captureStorageData);
                        console.log('  - window.captureStorageData:', window.captureStorageData);
                        
                        if (window.captureStorageData && typeof window.captureStorageData === 'function') {
                            console.log('🔄 Manually calling captureStorageData...');
                            window.captureStorageData();
                        } else {
                            console.error('❌ window.captureStorageData not found!');
                            console.log('🔍 Checking window properties:');
                            const keys = Object.keys(window).filter(key => key.includes('capture') || key.includes('Storage'));
                            console.log('  - Related keys:', keys);
                        }
                        
                    } catch (error) {
                        console.error('❌ Cookie test error:', error);
                        console.error('Error stack:', error.stack);
                    }
                    
                    console.log('🟡 === End Cookie Test ===');
                }
                
                window.testMockAPI = function() {
                    console.log('Testing mock API...');
                    // Create a mock response using data URI
                    const mockData = {
                        id: Math.floor(Math.random() * 1000),
                        title: 'Mock API Test Post',
                        body: 'This is a mock response body for testing from console',
                        userId: 1,
                        timestamp: new Date().toISOString(),
                        randomValue: Math.random()
                    };
                    
                    console.log('Mock data:', JSON.stringify(mockData, null, 2));
                    
                    // Simulate fetch with a data URL
                    return fetch('data:application/json;charset=utf-8,' + encodeURIComponent(JSON.stringify(mockData)))
                        .then(response => {
                            console.log('Mock API response status:', response.status);
                            console.log('Mock API response type:', response.headers.get('content-type'));
                            return response.json();
                        })
                        .then(data => {
                            console.log('Mock API success:', JSON.stringify(data, null, 2));
                            return data;
                        })
                        .catch(error => {
                            console.error('Mock API error:', error);
                            throw error;
                        });
                };
            </script>
        </body>
        </html>
        """
        
        // baseURL을 설정하여 Storage API가 정상 작동하도록 함
        loadHTMLString(html, baseURL: URL(string: "http://localhost"))
    }
}