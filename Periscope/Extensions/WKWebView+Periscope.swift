import WebKit
import Foundation

public extension WKWebView {
    
    private struct AssociatedKeys {
        static var isPeriscopeEnabled = "isPeriscopeEnabled"
        static var periscopeMessageHandler = "periscopeMessageHandler"
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
        guard !isPeriscopeEnabled else { return }
        
        // JavaScript 메시지 핸들러 등록
        let messageHandler = PeriscopeMessageHandler(debugger: debugger)
        objc_setAssociatedObject(self, &AssociatedKeys.periscopeMessageHandler, messageHandler, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        
        configuration.userContentController.add(messageHandler, name: "periscopeConsole")
        configuration.userContentController.add(messageHandler, name: "periscopeNetwork")
        configuration.userContentController.add(messageHandler, name: "periscopeStorage")
        
        // Console hook 스크립트 주입
        injectConsoleHookScript()
        
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
        
        configuration.userContentController.removeScriptMessageHandler(forName: "periscopeConsole")
        configuration.userContentController.removeScriptMessageHandler(forName: "periscopeNetwork")
        configuration.userContentController.removeScriptMessageHandler(forName: "periscopeStorage")
        objc_setAssociatedObject(self, &AssociatedKeys.periscopeMessageHandler, nil, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        
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
            
            let userScript = WKUserScript(source: scriptContent, injectionTime: .atDocumentStart, forMainFrameOnly: false)
            configuration.userContentController.addUserScript(userScript)
            return
        }
        #endif
        
        let userScript = WKUserScript(source: scriptContent, injectionTime: .atDocumentStart, forMainFrameOnly: false)
        configuration.userContentController.addUserScript(userScript)
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
        let inlineScript = """
        (function() {
            'use strict';
            
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
            window.fetch = function(...args) {
                const [url, options = {}] = args;
                const startTime = Date.now();
                const requestId = Math.random().toString(36).substr(2, 9);
                
                
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
                    const storageData = { localStorage: {}, sessionStorage: {}, cookies: document.cookie };
                    
                    for (let i = 0; i < localStorage.length; i++) {
                        const key = localStorage.key(i);
                        storageData.localStorage[key] = localStorage.getItem(key);
                    }
                    
                    for (let i = 0; i < sessionStorage.length; i++) {
                        const key = sessionStorage.key(i);
                        storageData.sessionStorage[key] = sessionStorage.getItem(key);
                    }
                    
                    console.log('🗃️ Capturing storage data:', JSON.stringify(storageData, null, 2));
                    
                    if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.periscopeStorage) {
                        window.webkit.messageHandlers.periscopeStorage.postMessage(storageData);
                        console.log('📤 Storage data sent to native');
                    } else {
                        console.warn('⚠️ Periscope: Storage message handler not available');
                    }
                } catch (e) {
                    console.error('❌ Storage capture error:', e);
                }
            }
            
            // 전역에서 접근 가능하도록 노출
            window.captureStorageData = captureStorageData;
            
            // Storage event monitoring - Hook setItem, removeItem, clear
            const originalSetItem = Storage.prototype.setItem;
            const originalRemoveItem = Storage.prototype.removeItem;
            const originalClear = Storage.prototype.clear;
            
            Storage.prototype.setItem = function(key, value) {
                try {
                    originalSetItem.apply(this, arguments);
                    setTimeout(captureStorageData, 10);
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
            
            setTimeout(captureStorageData, 100);
        })();
        """
        
        let userScript = WKUserScript(source: inlineScript, injectionTime: .atDocumentStart, forMainFrameOnly: false)
        configuration.userContentController.addUserScript(userScript)
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
                    localStorage.setItem('test-key', 'Test value at ' + new Date().toLocaleTimeString());
                    localStorage.setItem('user', JSON.stringify({name: 'John', age: 30}));
                    console.log('LocalStorage updated');
                }
                
                function testSessionStorage() {
                    sessionStorage.setItem('session-key', 'Session value at ' + new Date().toLocaleTimeString());
                    sessionStorage.setItem('temp-data', 'This will be cleared when browser closes');
                    console.log('SessionStorage updated');
                }
                
                function testCookies() {
                    document.cookie = 'test-cookie=value123; path=/';
                    document.cookie = 'user-preference=dark-mode; expires=' + new Date(Date.now() + 86400000).toUTCString();
                    console.log('Cookies updated');
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
        
        loadHTMLString(html, baseURL: nil)
    }
}