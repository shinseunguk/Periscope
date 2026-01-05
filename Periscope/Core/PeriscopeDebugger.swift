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
    }
    
    public func addLog(_ log: ConsoleLog) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            self.logs.append(log)
            
            // 로그 개수 제한
            if self.logs.count > self.maxLogCount {
                self.logs.removeFirst(self.logs.count - self.maxLogCount)
            }
            
            self.consoleModal?.addLog(log)
            self.delegate?.periscopeDebugger(self, didReceiveLog: log)
        }
    }
    
    public func clearLogs() {
        logs.removeAll()
        consoleModal?.clearLogs()
    }
    
    public func getAllLogs() -> [ConsoleLog] {
        return logs
    }
    
    public func getFilteredLogs(levels: [ConsoleLogLevel]) -> [ConsoleLog] {
        return logs.filter { levels.contains($0.level) }
    }
    
    public func addNetworkRequest(_ request: NetworkRequest) {
        DispatchQueue.main.async { [weak self] in
            print("📥 Adding network request: \(request.method) \(request.url)")
            self?.networkRequests[request.id] = request
            if let requests = self?.networkRequests.values {
                print("📊 Total network requests: \(requests.count)")
                self?.consoleModal?.updateNetworkData(Array(requests))
            }
        }
    }
    
    public func updateNetworkRequest(id: String, response: [String: Any]) {
        DispatchQueue.main.async { [weak self] in
            guard var request = self?.networkRequests[id] else { return }
            
            request.status = .success
            request.statusCode = response["status"] as? Int
            request.responseHeaders = response["headers"] as? [String: String]
            request.responseBody = response["body"] as? String
            request.duration = (response["duration"] as? Double).map { $0 / 1000 }
            
            self?.networkRequests[id] = request
            if let requests = self?.networkRequests.values {
                self?.consoleModal?.updateNetworkData(Array(requests))
            }
        }
    }
    
    public func updateNetworkRequestError(id: String, error: String, duration: Double?) {
        DispatchQueue.main.async { [weak self] in
            guard var request = self?.networkRequests[id] else { return }
            
            request.status = .error
            request.error = error
            request.duration = duration.map { $0 / 1000 }
            
            self?.networkRequests[id] = request
            if let requests = self?.networkRequests.values {
                self?.consoleModal?.updateNetworkData(Array(requests))
            }
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