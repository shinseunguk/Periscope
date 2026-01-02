(function() {
    'use strict';
    
    // 원본 console 메서드들을 백업
    const originalConsole = {
        log: console.log,
        info: console.info,
        warn: console.warn,
        error: console.error,
        debug: console.debug
    };
    
    // 원본 console을 전역에서 접근 가능하도록 노출
    window.originalConsole = originalConsole;
    
    // 메시지를 네이티브로 전송하는 헬퍼 함수
    function sendToNative(level, args) {
        try {
            // 인자들을 문자열로 변환
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
            
            // 소스 정보 수집 (스택 트레이스에서)
            let source = null;
            try {
                const stack = new Error().stack;
                const lines = stack.split('\n');
                // 첫 번째 줄은 Error, 두 번째는 현재 함수이므로 세 번째부터 찾기
                for (let i = 2; i < lines.length; i++) {
                    const line = lines[i].trim();
                    if (!line.includes('ConsoleHook.js') && !line.includes('webkit-masked-url')) {
                        source = line;
                        break;
                    }
                }
            } catch (e) {
                // 스택 트레이스 파싱 실패 시 무시
            }
            
            // WKWebView로 메시지 전송
            if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.periscopeConsole) {
                window.webkit.messageHandlers.periscopeConsole.postMessage({
                    level: level,
                    message: message,
                    source: source,
                    timestamp: new Date().getTime()
                });
            }
        } catch (e) {
            // 전송 실패 시 원본 console.error로 출력
            originalConsole.error('Periscope console hook error:', e);
        }
    }
    
    // console.log 후킹
    console.log = function() {
        originalConsole.log.apply(console, arguments);
        sendToNative('log', Array.from(arguments));
    };
    
    // console.info 후킹
    console.info = function() {
        originalConsole.info.apply(console, arguments);
        sendToNative('info', Array.from(arguments));
    };
    
    // console.warn 후킹
    console.warn = function() {
        originalConsole.warn.apply(console, arguments);
        sendToNative('warn', Array.from(arguments));
    };
    
    // console.error 후킹
    console.error = function() {
        originalConsole.error.apply(console, arguments);
        sendToNative('error', Array.from(arguments));
    };
    
    // console.debug 후킹
    console.debug = function() {
        originalConsole.debug.apply(console, arguments);
        sendToNative('debug', Array.from(arguments));
    };
    
    // 글로벌 에러 핸들러 추가 (Cross-origin 에러 필터링)
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
    
    // Promise rejection 핸들러 추가
    window.addEventListener('unhandledrejection', function(event) {
        const reason = event.reason ? JSON.stringify(event.reason) : 'Unknown reason';
        sendToNative('error', [`Unhandled Promise Rejection: ${reason}`]);
    });
    
    // 초기화 완료 메시지
    sendToNative('info', ['Periscope console hook initialized']);
    
    // 네트워크 요청 인터셉트
    const originalFetch = window.fetch;
    const originalXHR = window.XMLHttpRequest.prototype.open;
    const xhrSend = window.XMLHttpRequest.prototype.send;
    
    // Fetch API 후킹
    window.fetch = function(...args) {
        try {
            const [url, options = {}] = args;
            const startTime = Date.now();
            const requestId = Math.random().toString(36).substr(2, 9);
            
            // 요청 정보 전송
            if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.periscopeNetwork) {
                window.webkit.messageHandlers.periscopeNetwork.postMessage({
                    type: 'request',
                    id: requestId,
                    url: url.toString(),
                    method: options.method || 'GET',
                    headers: options.headers || {},
                    timestamp: startTime
                });
            }
        
            return originalFetch.apply(this, args).then(response => {
                try {
                    const duration = Date.now() - startTime;
                    
                    // 응답 정보 전송
                    if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.periscopeNetwork) {
                        response.clone().text().then(body => {
                            try {
                                window.webkit.messageHandlers.periscopeNetwork.postMessage({
                                    type: 'response',
                                    id: requestId,
                                    status: response.status,
                                    statusText: response.statusText,
                                    headers: Object.fromEntries(response.headers.entries()),
                                    body: body.substr(0, 1000), // 처음 1000자만
                                    duration: duration,
                                    timestamp: Date.now()
                                });
                            } catch (e) {
                                originalConsole.error('Error sending response data:', e);
                            }
                        }).catch(e => {
                            originalConsole.error('Error reading response body:', e);
                        });
                    }
                    
                    return response;
                } catch (e) {
                    originalConsole.error('Error in fetch response handler:', e);
                    return response;
                }
            }).catch(error => {
                try {
                    // 에러 정보 전송
                    if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.periscopeNetwork) {
                        window.webkit.messageHandlers.periscopeNetwork.postMessage({
                            type: 'error',
                            id: requestId,
                            error: error.message,
                            duration: Date.now() - startTime,
                            timestamp: Date.now()
                        });
                    }
                } catch (e) {
                    originalConsole.error('Error sending error data:', e);
                }
                throw error;
            });
        } catch (e) {
            originalConsole.error('Error in fetch hook:', e);
            return originalFetch.apply(this, args);
        }
    };
    
    // XMLHttpRequest 후킹
    const xhrMap = new WeakMap();
    
    window.XMLHttpRequest.prototype.open = function(method, url, ...args) {
        xhrMap.set(this, {
            method: method,
            url: url,
            startTime: Date.now(),
            id: Math.random().toString(36).substr(2, 9)
        });
        return originalXHR.apply(this, [method, url, ...args]);
    };
    
    window.XMLHttpRequest.prototype.send = function(body) {
        const info = xhrMap.get(this);
        
        if (info && window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.periscopeNetwork) {
            window.webkit.messageHandlers.periscopeNetwork.postMessage({
                type: 'request',
                id: info.id,
                url: info.url,
                method: info.method,
                timestamp: info.startTime
            });
            
            this.addEventListener('load', function() {
                // Collect response headers
                const responseHeaders = {};
                const headerString = this.getAllResponseHeaders();
                if (headerString) {
                    headerString.split('\r\n').forEach(line => {
                        const parts = line.split(': ');
                        if (parts.length === 2) {
                            responseHeaders[parts[0]] = parts[1];
                        }
                    });
                }
                
                window.webkit.messageHandlers.periscopeNetwork.postMessage({
                    type: 'response',
                    id: info.id,
                    status: this.status,
                    statusText: this.statusText,
                    headers: responseHeaders,
                    body: this.responseText ? this.responseText.substr(0, 5000) : '',
                    duration: Date.now() - info.startTime,
                    timestamp: Date.now()
                });
            });
            
            this.addEventListener('error', function() {
                window.webkit.messageHandlers.periscopeNetwork.postMessage({
                    type: 'error',
                    id: info.id,
                    error: 'Network error',
                    duration: Date.now() - info.startTime,
                    timestamp: Date.now()
                });
            });
        }
        
        return xhrSend.apply(this, arguments);
    };
    
    // 스토리지 모니터링
    function captureStorageData() {
        const storageData = {
            localStorage: {},
            sessionStorage: {},
            cookies: document.cookie
        };
        
        // localStorage 데이터 수집
        try {
            for (let i = 0; i < localStorage.length; i++) {
                const key = localStorage.key(i);
                storageData.localStorage[key] = localStorage.getItem(key);
            }
        } catch (e) {}
        
        // sessionStorage 데이터 수집
        try {
            for (let i = 0; i < sessionStorage.length; i++) {
                const key = sessionStorage.key(i);
                storageData.sessionStorage[key] = sessionStorage.getItem(key);
            }
        } catch (e) {}
        
        // 네이티브로 전송
        if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.periscopeStorage) {
            window.webkit.messageHandlers.periscopeStorage.postMessage(storageData);
        }
    }
    
    // Storage 이벤트 모니터링
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
    
    // 초기 스토리지 데이터 캡처
    setTimeout(captureStorageData, 100);
    
})();