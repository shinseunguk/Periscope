import UIKit
import WebKit

public protocol PeriscopeDebuggerDelegate: AnyObject {
    func periscopeDebugger(_ debugger: PeriscopeDebugger, didReceiveLog log: ConsoleLog)
    func periscopeDebuggerDidToggleVisibility(_ debugger: PeriscopeDebugger, isVisible: Bool)
}

public class PeriscopeDebugger: NSObject {
    public static let shared = PeriscopeDebugger()
    
    public weak var delegate: PeriscopeDebuggerDelegate?
    
    private var floatingButton: PeriscopeFloatingButton?
    private var consoleModal: PeriscopeConsoleModal?
    private var targetWindow: UIWindow?
    private var logs: [ConsoleLog] = []
    private var networkRequests: [String: NetworkRequest] = [:]
    private var currentStorageData: StorageData?
    
    public var isEnabled: Bool = false {
        didSet {
            if isEnabled {
                setupFloatingButton()
            } else {
                removeFloatingButton()
                hideConsole()
            }
        }
    }
    
    public var maxLogCount: Int = 1000
    
    private override init() {
        super.init()
        
        // 앱이 백그라운드로 갈 때 메모리 정리
        NotificationCenter.default.addObserver(
            forName: UIApplication.didEnterBackgroundNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.cleanupMemoryOnBackground()
        }
    }
    
    private func cleanupMemoryOnBackground() {
        // 백그라운드 시 과도한 데이터 정리
        if logs.count > 50 {
            logs = Array(logs.suffix(50))
        }
        
        if networkRequests.count > 10 {
            let sortedRequests = networkRequests.values.sorted { $0.requestTime > $1.requestTime }
            networkRequests.removeAll()
            for request in sortedRequests.prefix(10) {
                networkRequests[request.id] = request
            }
        }
        
        consoleModal?.cleanupMemoryOnBackground()
    }
    
    // MARK: - Public Methods
    
    public func enable(in window: UIWindow? = nil) {
        self.targetWindow = window ?? UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
            .first { $0.isKeyWindow }
        
        isEnabled = true
    }
    
    public func disable() {
        isEnabled = false
        
        // 메모리 정리
        logs.removeAll()
        networkRequests.removeAll()
        
        // Modal 메모리 정리
        consoleModal?.removeFromSuperview()
        consoleModal = nil
        
        // 플로팅 버튼 정리
        floatingButton?.removeFromSuperview()
        floatingButton = nil
    }
    
    public func addLog(_ log: ConsoleLog) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            // 메모리 절약: PeriscopeDebugger에는 저장하지 않고 Modal에만 전달
            // (중복 저장 방지)
            self.consoleModal?.addLog(log)
            self.delegate?.periscopeDebugger(self, didReceiveLog: log)
        }
    }
    
    public func clearLogs() {
        logs.removeAll()
        consoleModal?.clearLogs()
    }
    
    public func getAllLogs() -> [ConsoleLog] {
        // Modal에서 로그를 가져옴 (중복 저장 방지)
        return consoleModal?.logs ?? []
    }
    
    public func getFilteredLogs(levels: [ConsoleLogLevel]) -> [ConsoleLog] {
        return getAllLogs().filter { levels.contains($0.level) }
    }
    
    public func addNetworkRequest(_ request: NetworkRequest) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            PeriscopeLogger.log("Adding network request: \(request.method) \(request.url)")
            
            // 네트워크 요청 개수 제한 (메모리 누수 방지)
            if self.networkRequests.count >= 50 {
                // 가장 오래된 요청 제거
                let oldestKey = self.networkRequests.keys.min { a, b in
                    let reqA = self.networkRequests[a]?.requestTime ?? Date()
                    let reqB = self.networkRequests[b]?.requestTime ?? Date()
                    return reqA < reqB
                }
                if let key = oldestKey {
                    self.networkRequests.removeValue(forKey: key)
                }
            }
            
            self.networkRequests[request.id] = request
            let requests = Array(self.networkRequests.values)
            PeriscopeLogger.log("Total network requests: \(requests.count)")
            self.consoleModal?.updateNetworkData(requests)
        }
    }
    
    public func updateNetworkRequest(id: String, response: [String: Any]) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self,
                  var request = self.networkRequests[id] else { return }
            
            request.status = .success
            request.statusCode = response["status"] as? Int
            request.responseHeaders = response["headers"] as? [String: String]
            request.responseBody = response["body"] as? String
            request.duration = (response["duration"] as? Double).map { $0 / 1000 }
            
            self.networkRequests[id] = request
            let requests = Array(self.networkRequests.values)
            self.consoleModal?.updateNetworkData(requests)
        }
    }
    
    public func updateNetworkRequestError(id: String, error: String, duration: Double?) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self,
                  var request = self.networkRequests[id] else { return }
            
            request.status = .error
            request.error = error
            request.duration = duration.map { $0 / 1000 }
            
            self.networkRequests[id] = request
            let requests = Array(self.networkRequests.values)
            self.consoleModal?.updateNetworkData(requests)
        }
    }
    
    public func updateStorageData(_ data: StorageData) {
        DispatchQueue.main.async { [weak self] in
            self?.currentStorageData = data
            self?.consoleModal?.updateStorageData(data)
        }
    }
    
    public func clearNetworkRequests() {
        networkRequests.removeAll()
        consoleModal?.updateNetworkData([])
    }
    
    // MARK: - Private Methods
    
    private func setupFloatingButton() {
        guard let window = targetWindow else { return }
        
        floatingButton = PeriscopeFloatingButton { [weak self] in
            self?.toggleConsole()
        }
        
        if let button = floatingButton {
            window.addSubview(button)
            button.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                button.trailingAnchor.constraint(equalTo: window.safeAreaLayoutGuide.trailingAnchor, constant: -20),
                button.bottomAnchor.constraint(equalTo: window.safeAreaLayoutGuide.bottomAnchor, constant: -20),
                button.widthAnchor.constraint(equalToConstant: 60),
                button.heightAnchor.constraint(equalToConstant: 60)
            ])
        }
    }
    
    private func removeFloatingButton() {
        floatingButton?.removeFromSuperview()
        floatingButton = nil
    }
    
    private func toggleConsole() {
        if consoleModal?.isVisible == true {
            hideConsole()
        } else {
            showConsole()
        }
    }
    
    private func showConsole() {
        guard let window = targetWindow else { return }
        
        if consoleModal == nil {
            consoleModal = PeriscopeConsoleModal(logs: logs)
            consoleModal?.delegate = self
            
            // 이미 저장된 네트워크 요청과 스토리지 데이터 전달
            if !networkRequests.isEmpty {
                let requests = Array(networkRequests.values)
                consoleModal?.updateNetworkData(requests)
            }
            
            if let storageData = currentStorageData {
                consoleModal?.updateStorageData(storageData)
            }
        }
        
        consoleModal?.show(in: window)
        delegate?.periscopeDebuggerDidToggleVisibility(self, isVisible: true)
    }
    
    private func hideConsole() {
        consoleModal?.hide()
        delegate?.periscopeDebuggerDidToggleVisibility(self, isVisible: false)
    }
}

// MARK: - PeriscopeConsoleModalDelegate

extension PeriscopeDebugger: PeriscopeConsoleModalDelegate {
    public func periscopeConsoleModalDidRequestClose(_ modal: PeriscopeConsoleModal) {
        hideConsole()
    }
    
    public func periscopeConsoleModalDidRequestClear(_ modal: PeriscopeConsoleModal) {
        clearLogs()
    }
}