import UIKit
import WebKit

public protocol PeriscopeConsoleModalDelegate: AnyObject {
    func periscopeConsoleModalDidRequestClose(_ modal: PeriscopeConsoleModal)
    func periscopeConsoleModalDidRequestClear(_ modal: PeriscopeConsoleModal)
}

public class PeriscopeConsoleModal: UIView, UITextFieldDelegate {
    
    public weak var delegate: PeriscopeConsoleModalDelegate?
    
    private var backgroundView: UIView!
    private var containerView: UIView!
    private var headerView: UIView!
    private var tabSegmentedControl: UISegmentedControl!
    private var closeButton: UIButton!
    private var clearButton: UIButton!
    private var filterStackView: UIStackView!
    private var consoleInputContainer: UIView!
    private var consoleInputField: UITextField!
    private var executeButton: UIButton!
    private var tableView: UITableView!
    private var networkTableView: UITableView!
    private var storageTableView: UITableView!
    
    internal var logs: [ConsoleLog] = []
    private var filteredLogs: [ConsoleLog] = []
    private var selectedFilters: Set<ConsoleLogLevel> = Set(ConsoleLogLevel.allCases)
    private var networkRequests: [NetworkRequest] = []
    private var storageData: StorageData?
    
    public var isVisible: Bool = false
    
    public init(logs: [ConsoleLog] = []) {
        self.logs = logs
        self.filteredLogs = logs
        super.init(frame: .zero)
        setupUI()
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupUI()
    }
    
    private func setupUI() {
        setupBackground()
        setupContainer()
        setupHeader()
        setupFilters()
        setupConsoleInput()
        setupTableView()
        setupConstraints()
        
        isHidden = true
    }
    
    private func setupBackground() {
        backgroundView = UIView()
        backgroundView.backgroundColor = UIColor.black.withAlphaComponent(0.5)
        backgroundView.translatesAutoresizingMaskIntoConstraints = false
        
        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(backgroundTapped))
        backgroundView.addGestureRecognizer(tapGesture)
        
        addSubview(backgroundView)
    }
    
    private func setupContainer() {
        containerView = UIView()
        containerView.backgroundColor = UIColor.systemBackground
        containerView.layer.cornerRadius = 16
        containerView.layer.maskedCorners = [.layerMinXMinYCorner, .layerMaxXMinYCorner]
        containerView.layer.shadowColor = UIColor.black.cgColor
        containerView.layer.shadowOffset = CGSize(width: 0, height: -4)
        containerView.layer.shadowRadius = 12
        containerView.layer.shadowOpacity = 0.3
        containerView.translatesAutoresizingMaskIntoConstraints = false
        
        addSubview(containerView)
    }
    
    private func setupHeader() {
        headerView = UIView()
        headerView.backgroundColor = UIColor.systemGray6
        headerView.translatesAutoresizingMaskIntoConstraints = false
        
        // 탭 세그먼트 컨트롤
        tabSegmentedControl = UISegmentedControl(items: ["Console", "Network", "Storage"])
        tabSegmentedControl.selectedSegmentIndex = 0
        tabSegmentedControl.addTarget(self, action: #selector(tabChanged(_:)), for: .valueChanged)
        tabSegmentedControl.translatesAutoresizingMaskIntoConstraints = false
        
        // 닫기 버튼
        closeButton = UIButton(type: .system)
        closeButton.setTitle("✕", for: .normal)
        closeButton.titleLabel?.font = UIFont.systemFont(ofSize: 18, weight: .medium)
        closeButton.tintColor = UIColor.label
        closeButton.addTarget(self, action: #selector(closeButtonTapped), for: .touchUpInside)
        closeButton.translatesAutoresizingMaskIntoConstraints = false
        
        // 클리어 버튼
        clearButton = UIButton(type: .system)
        clearButton.setTitle("Clear", for: .normal)
        clearButton.titleLabel?.font = UIFont.systemFont(ofSize: 14, weight: .medium)
        clearButton.tintColor = UIColor.systemBlue
        clearButton.addTarget(self, action: #selector(clearButtonTapped), for: .touchUpInside)
        clearButton.translatesAutoresizingMaskIntoConstraints = false
        
        headerView.addSubview(tabSegmentedControl)
        headerView.addSubview(closeButton)
        headerView.addSubview(clearButton)
        containerView.addSubview(headerView)
    }
    
    private func setupFilters() {
        filterStackView = UIStackView()
        filterStackView.axis = .horizontal
        filterStackView.distribution = .fillEqually
        filterStackView.spacing = 8
        filterStackView.translatesAutoresizingMaskIntoConstraints = false
        
        for level in ConsoleLogLevel.allCases {
            let button = createFilterButton(for: level)
            filterStackView.addArrangedSubview(button)
        }
        
        containerView.addSubview(filterStackView)
    }
    
    private func setupConsoleInput() {
        consoleInputContainer = UIView()
        consoleInputContainer.backgroundColor = UIColor.systemGray6
        consoleInputContainer.layer.cornerRadius = 8
        consoleInputContainer.layer.borderWidth = 1
        consoleInputContainer.layer.borderColor = UIColor.systemGray4.cgColor
        consoleInputContainer.translatesAutoresizingMaskIntoConstraints = false
        
        consoleInputField = UITextField()
        consoleInputField.placeholder = "JavaScript code..."
        consoleInputField.font = UIFont.monospacedSystemFont(ofSize: 14, weight: .regular)
        consoleInputField.borderStyle = .none
        consoleInputField.autocapitalizationType = .none
        consoleInputField.autocorrectionType = .no
        consoleInputField.spellCheckingType = .no
        consoleInputField.translatesAutoresizingMaskIntoConstraints = false
        consoleInputField.delegate = self
        
        executeButton = UIButton(type: .system)
        executeButton.setTitle("▶", for: .normal)
        executeButton.titleLabel?.font = UIFont.systemFont(ofSize: 16, weight: .bold)
        executeButton.tintColor = UIColor.systemBlue
        executeButton.addTarget(self, action: #selector(executeButtonTapped), for: .touchUpInside)
        executeButton.translatesAutoresizingMaskIntoConstraints = false
        
        consoleInputContainer.addSubview(consoleInputField)
        consoleInputContainer.addSubview(executeButton)
        containerView.addSubview(consoleInputContainer)
        
        NSLayoutConstraint.activate([
            consoleInputField.leadingAnchor.constraint(equalTo: consoleInputContainer.leadingAnchor, constant: 12),
            consoleInputField.centerYAnchor.constraint(equalTo: consoleInputContainer.centerYAnchor),
            consoleInputField.trailingAnchor.constraint(equalTo: executeButton.leadingAnchor, constant: -8),
            
            executeButton.trailingAnchor.constraint(equalTo: consoleInputContainer.trailingAnchor, constant: -12),
            executeButton.centerYAnchor.constraint(equalTo: consoleInputContainer.centerYAnchor),
            executeButton.widthAnchor.constraint(equalToConstant: 30),
            executeButton.heightAnchor.constraint(equalToConstant: 30)
        ])
    }
    
    private func createFilterButton(for level: ConsoleLogLevel) -> UIButton {
        let button = UIButton(type: .system)
        button.setTitle(level.displayName, for: .normal)
        button.titleLabel?.font = UIFont.systemFont(ofSize: 12, weight: .medium)
        button.layer.cornerRadius = 4
        button.layer.borderWidth = 1
        button.tag = ConsoleLogLevel.allCases.firstIndex(of: level) ?? 0
        button.addTarget(self, action: #selector(filterButtonTapped(_:)), for: .touchUpInside)
        
        updateFilterButtonAppearance(button, isSelected: true)
        
        return button
    }
    
    private func updateFilterButtonAppearance(_ button: UIButton, isSelected: Bool) {
        if isSelected {
            button.backgroundColor = UIColor.systemBlue
            button.tintColor = UIColor.white
            button.layer.borderColor = UIColor.systemBlue.cgColor
        } else {
            button.backgroundColor = UIColor.clear
            button.tintColor = UIColor.label
            button.layer.borderColor = UIColor.systemGray4.cgColor
        }
    }
    
    private func setupTableView() {
        // Console table view
        tableView = UITableView()
        tableView.backgroundColor = UIColor.systemBackground
        tableView.separatorStyle = .singleLine
        tableView.separatorColor = UIColor.systemGray5
        tableView.delegate = self
        tableView.dataSource = self
        tableView.register(ConsoleLogCell.self, forCellReuseIdentifier: "ConsoleLogCell")
        tableView.translatesAutoresizingMaskIntoConstraints = false
        
        // Network table view
        networkTableView = UITableView()
        networkTableView.backgroundColor = UIColor.systemBackground
        networkTableView.separatorStyle = .singleLine
        networkTableView.separatorColor = UIColor.systemGray5
        networkTableView.delegate = self
        networkTableView.dataSource = self
        networkTableView.register(NetworkRequestCell.self, forCellReuseIdentifier: "NetworkRequestCell")
        networkTableView.translatesAutoresizingMaskIntoConstraints = false
        networkTableView.isHidden = true
        
        // Storage table view
        storageTableView = UITableView()
        storageTableView.backgroundColor = UIColor.systemBackground
        storageTableView.separatorStyle = .singleLine
        storageTableView.separatorColor = UIColor.systemGray5
        storageTableView.delegate = self
        storageTableView.dataSource = self
        storageTableView.register(StorageItemCell.self, forCellReuseIdentifier: "StorageItemCell")
        storageTableView.translatesAutoresizingMaskIntoConstraints = false
        storageTableView.isHidden = true
        
        containerView.addSubview(tableView)
        containerView.addSubview(networkTableView)
        containerView.addSubview(storageTableView)
    }
    
    private func setupConstraints() {
        NSLayoutConstraint.activate([
            // Background
            backgroundView.topAnchor.constraint(equalTo: topAnchor),
            backgroundView.leadingAnchor.constraint(equalTo: leadingAnchor),
            backgroundView.trailingAnchor.constraint(equalTo: trailingAnchor),
            backgroundView.bottomAnchor.constraint(equalTo: bottomAnchor),
            
            // Container
            containerView.leadingAnchor.constraint(equalTo: leadingAnchor),
            containerView.trailingAnchor.constraint(equalTo: trailingAnchor),
            containerView.bottomAnchor.constraint(equalTo: bottomAnchor),
            containerView.heightAnchor.constraint(equalTo: heightAnchor, multiplier: 0.5),
            
            // Header
            headerView.topAnchor.constraint(equalTo: containerView.topAnchor),
            headerView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
            headerView.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
            headerView.heightAnchor.constraint(equalToConstant: 50),
            
            // Tab Segmented Control
            tabSegmentedControl.centerYAnchor.constraint(equalTo: headerView.centerYAnchor),
            tabSegmentedControl.leadingAnchor.constraint(equalTo: headerView.leadingAnchor, constant: 16),
            tabSegmentedControl.widthAnchor.constraint(equalToConstant: 240),
            
            // Close button
            closeButton.centerYAnchor.constraint(equalTo: headerView.centerYAnchor),
            closeButton.trailingAnchor.constraint(equalTo: headerView.trailingAnchor, constant: -16),
            closeButton.widthAnchor.constraint(equalToConstant: 30),
            closeButton.heightAnchor.constraint(equalToConstant: 30),
            
            // Clear button
            clearButton.centerYAnchor.constraint(equalTo: headerView.centerYAnchor),
            clearButton.trailingAnchor.constraint(equalTo: closeButton.leadingAnchor, constant: -16),
            
            // Filter stack
            filterStackView.topAnchor.constraint(equalTo: headerView.bottomAnchor, constant: 8),
            filterStackView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor, constant: 16),
            filterStackView.trailingAnchor.constraint(equalTo: containerView.trailingAnchor, constant: -16),
            filterStackView.heightAnchor.constraint(equalToConstant: 32),
            
            // Console input
            consoleInputContainer.topAnchor.constraint(equalTo: filterStackView.bottomAnchor, constant: 8),
            consoleInputContainer.leadingAnchor.constraint(equalTo: containerView.leadingAnchor, constant: 16),
            consoleInputContainer.trailingAnchor.constraint(equalTo: containerView.trailingAnchor, constant: -16),
            consoleInputContainer.heightAnchor.constraint(equalToConstant: 40),
            
            // Table views
            tableView.topAnchor.constraint(equalTo: consoleInputContainer.bottomAnchor, constant: 8),
            tableView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: containerView.bottomAnchor),
            
            networkTableView.topAnchor.constraint(equalTo: headerView.bottomAnchor, constant: 8),
            networkTableView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
            networkTableView.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
            networkTableView.bottomAnchor.constraint(equalTo: containerView.bottomAnchor),
            
            storageTableView.topAnchor.constraint(equalTo: headerView.bottomAnchor, constant: 8),
            storageTableView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
            storageTableView.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
            storageTableView.bottomAnchor.constraint(equalTo: containerView.bottomAnchor)
        ])
    }
    
    // MARK: - Public Methods
    
    public func show(in view: UIView) {
        guard !isVisible else { return }
        
        frame = view.bounds
        view.addSubview(self)
        
        // 애니메이션으로 나타나기
        containerView.transform = CGAffineTransform(translationX: 0, y: bounds.height * 0.5)
        backgroundView.alpha = 0
        isHidden = false
        
        UIView.animate(withDuration: 0.3, delay: 0, usingSpringWithDamping: 0.8, initialSpringVelocity: 0) {
            self.containerView.transform = .identity
            self.backgroundView.alpha = 1
        }
        
        isVisible = true
        scrollToBottom()
    }
    
    public func hide() {
        guard isVisible else { return }
        
        UIView.animate(withDuration: 0.3, animations: {
            self.containerView.transform = CGAffineTransform(translationX: 0, y: self.bounds.height * 0.5)
            self.backgroundView.alpha = 0
        }) { _ in
            self.removeFromSuperview()
            self.isHidden = true
            self.isVisible = false
            
            // Clean up data when modal is hidden to reduce memory usage
            if self.logs.count > 1000 {
                self.logs = Array(self.logs.suffix(500))
                self.applyFilters()
            }
            if self.networkRequests.count > 100 {
                self.networkRequests = Array(self.networkRequests.prefix(50))
            }
        }
    }
    
    public func addLog(_ log: ConsoleLog) {
        logs.append(log)
        
        // 로그 개수 제한 (메모리 누수 방지)
        if logs.count > 500 {
            logs.removeFirst(logs.count - 300) // 300개만 유지
        }
        
        applyFilters()
        
        DispatchQueue.main.async { [weak self] in
            self?.tableView.reloadData()
            self?.scrollToBottom()
        }
    }
    
    public func clearLogs() {
        if tabSegmentedControl.selectedSegmentIndex == 0 {
            logs.removeAll()
            filteredLogs.removeAll()
            
            DispatchQueue.main.async { [weak self] in
                self?.tableView.reloadData()
            }
        } else if tabSegmentedControl.selectedSegmentIndex == 1 {
            // Clear network requests
            networkRequests.removeAll()
            DispatchQueue.main.async { [weak self] in
                self?.networkTableView.reloadData()
            }
        }
    }
    
    private func scrollToBottom() {
        guard filteredLogs.count > 0 else { return }
        
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            // Double-check the count after async dispatch
            guard self.filteredLogs.count > 0 else { return }
            
            // Ensure table view has been loaded and has data
            guard self.tableView.numberOfRows(inSection: 0) > 0 else { return }
            
            let indexPath = IndexPath(row: self.filteredLogs.count - 1, section: 0)
            
            // Additional safety check for valid index path
            guard indexPath.row < self.tableView.numberOfRows(inSection: 0) else { return }
            
            self.tableView.scrollToRow(at: indexPath, at: .bottom, animated: true)
        }
    }
    
    private func applyFilters() {
        filteredLogs = logs.filter { selectedFilters.contains($0.level) }
    }
    
    // MARK: - Actions
    
    @objc private func backgroundTapped() {
        delegate?.periscopeConsoleModalDidRequestClose(self)
    }
    
    @objc private func closeButtonTapped() {
        delegate?.periscopeConsoleModalDidRequestClose(self)
    }
    
    @objc private func clearButtonTapped() {
        delegate?.periscopeConsoleModalDidRequestClear(self)
    }
    
    @objc private func executeButtonTapped() {
        executeJavaScript()
    }
    
    private func executeJavaScript() {
        guard let code = consoleInputField.text, !code.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return
        }
        
        // 입력된 코드를 먼저 로그에 표시
        let inputLog = ConsoleLog(level: .info, message: "> \(code)", source: "Console")
        addLog(inputLog)
        
        // WebView를 찾아서 JavaScript 실행
        if let webView = findWebView() {
            consoleInputField.text = ""
            consoleInputField.resignFirstResponder()
            
            PeriscopeLogger.log("Found WebView, executing: \(code)")
            
            // console.log 명령어를 완전히 우회
            if code.contains("console.log(") {
                // console.log 내용만 추출해서 출력
                let pattern = #"console\.log\((.+)\)"#
                if let regex = try? NSRegularExpression(pattern: pattern),
                   let match = regex.firstMatch(in: code, range: NSRange(code.startIndex..., in: code)),
                   let argRange = Range(match.range(at: 1), in: code) {
                    let rawArgument = String(code[argRange])
                    
                    // 스마트 따옴표 정규화
                    let normalizedArgument = rawArgument
                        .replacingOccurrences(of: "'", with: "'")   // 왼쪽 스마트 따옴표
                        .replacingOccurrences(of: "'", with: "'")   // 오른쪽 스마트 따옴표
                        .replacingOccurrences(of: "\u{201C}", with: "\"") // 왼쪽 스마트 큰따옴표
                        .replacingOccurrences(of: "\u{201D}", with: "\"") // 오른쪽 스마트 큰따옴표
                    
                    PeriscopeLogger.log("Raw argument: \(rawArgument)")
                    PeriscopeLogger.log("Normalized argument: \(normalizedArgument)")
                    
                    // 인수를 평가하고 결과를 출력
                    let evaluateCode = """
                    (function() {
                        try {
                            var result = \(normalizedArgument);
                            return result;
                        } catch (e) {
                            return 'Error: ' + e.message;
                        }
                    })()
                    """
                    
                    PeriscopeLogger.log("Executing normalized argument: \(normalizedArgument)")
                    PeriscopeLogger.log("Full evaluate code: \(evaluateCode)")
                    
                    webView.evaluateJavaScript(evaluateCode) { [weak self] result, error in
                        DispatchQueue.main.async {
                            if let error = error {
                                PeriscopeLogger.error("JavaScript error: \(error)")
                                PeriscopeLogger.error("Error domain: \(error._domain)")
                                PeriscopeLogger.error("Error code: \(error._code)")
                                if let userInfo = (error as NSError).userInfo as? [String: Any] {
                                    PeriscopeLogger.error("Error userInfo: \(userInfo)")
                                }
                                let errorLog = ConsoleLog(level: .error, message: "Error: \(error.localizedDescription)", source: "Console")
                                self?.addLog(errorLog)
                            } else if let result = result {
                                PeriscopeLogger.log("JavaScript result: \(result)")
                                // console.log의 출력을 시뮬레이트
                                let logMessage = ConsoleLog(level: .log, message: "\(result)", source: "Console")
                                self?.addLog(logMessage)
                                // console.log는 undefined 반환
                                let undefinedLog = ConsoleLog(level: .log, message: "← undefined", source: "Console")
                                self?.addLog(undefinedLog)
                            }
                        }
                    }
                } else {
                    let errorLog = ConsoleLog(level: .error, message: "Invalid console.log syntax", source: "Console")
                    addLog(errorLog)
                }
            } else {
                // 다른 코드는 직접 실행 (Promise 처리 포함)
                PeriscopeLogger.log("Executing other code directly: \(code)")
                
                let wrappedCode = """
                (function() {
                    try {
                        let result = \(code);
                        if (result && typeof result.then === 'function') {
                            // Promise인 경우
                            result.then(data => {
                                console.log('Promise resolved:', JSON.stringify(data, null, 2));
                            }).catch(error => {
                                console.error('Promise rejected:', error);
                            });
                            return 'Promise executing... check console for results';
                        } else {
                            // 일반 값인 경우
                            return result;
                        }
                    } catch (e) {
                        return 'Error: ' + e.message;
                    }
                })()
                """
                
                webView.evaluateJavaScript(wrappedCode) { [weak self] result, error in
                    DispatchQueue.main.async {
                        if let error = error {
                            PeriscopeLogger.error("Direct execution error: \(error)")
                            PeriscopeLogger.error("Error domain: \(error._domain)")
                            PeriscopeLogger.error("Error code: \(error._code)")
                            if let userInfo = (error as NSError).userInfo as? [String: Any] {
                                PeriscopeLogger.error("Error userInfo: \(userInfo)")
                            }
                            let errorLog = ConsoleLog(level: .error, message: "Error: \(error.localizedDescription)", source: "Console")
                            self?.addLog(errorLog)
                        } else if let result = result {
                            // nil이 아닌 결과
                            if "\(result)" == "Optional(<null>)" || "\(result)" == "<null>" {
                                let nullLog = ConsoleLog(level: .log, message: "← null", source: "Console")
                                self?.addLog(nullLog)
                            } else {
                                let resultString = "\(result)"
                                let resultLog = ConsoleLog(level: .log, message: "← \(resultString)", source: "Console")
                                self?.addLog(resultLog)
                            }
                        } else {
                            // nil 결과 (undefined)
                            let undefinedLog = ConsoleLog(level: .log, message: "← undefined", source: "Console")
                            self?.addLog(undefinedLog)
                        }
                    }
                }
            }
        } else {
            let errorLog = ConsoleLog(level: .error, message: "WebView not found - make sure a web page is loaded", source: "Console")
            addLog(errorLog)
        }
    }
    
    private func findWebView() -> WKWebView? {
        // 현재 윈도우에서 WKWebView 찾기
        guard let window = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .flatMap({ $0.windows })
            .first(where: { $0.isKeyWindow }) else { return nil }
        
        return findWebViewInView(window)
    }
    
    private func findWebViewInView(_ view: UIView) -> WKWebView? {
        if let webView = view as? WKWebView {
            return webView
        }
        
        for subview in view.subviews {
            if let webView = findWebViewInView(subview) {
                return webView
            }
        }
        
        return nil
    }
    
    // MARK: - UITextFieldDelegate
    
    public func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        if textField == consoleInputField {
            executeJavaScript()
            return false
        }
        return true
    }
    
    @objc private func filterButtonTapped(_ sender: UIButton) {
        let level = ConsoleLogLevel.allCases[sender.tag]
        
        if selectedFilters.contains(level) {
            selectedFilters.remove(level)
            updateFilterButtonAppearance(sender, isSelected: false)
        } else {
            selectedFilters.insert(level)
            updateFilterButtonAppearance(sender, isSelected: true)
        }
        
        applyFilters()
        tableView.reloadData()
    }
    
    @objc private func tabChanged(_ sender: UISegmentedControl) {
        PeriscopeLogger.log("Tab changed to: \(sender.selectedSegmentIndex) (0=Console, 1=Network, 2=Storage)")
        switch sender.selectedSegmentIndex {
        case 0: // Console
            filterStackView.isHidden = false
            consoleInputContainer.isHidden = false
            tableView.isHidden = false
            networkTableView.isHidden = true
            storageTableView.isHidden = true
            clearButton.isHidden = false
        case 1: // Network  
            filterStackView.isHidden = true
            consoleInputContainer.isHidden = true
            tableView.isHidden = true
            networkTableView.isHidden = false
            storageTableView.isHidden = true
            clearButton.isHidden = false
            PeriscopeLogger.log("Network tab selected - showing \(networkRequests.count) requests")
        case 2: // Storage
            filterStackView.isHidden = true
            consoleInputContainer.isHidden = true
            tableView.isHidden = true
            networkTableView.isHidden = true
            storageTableView.isHidden = false
            clearButton.isHidden = true
        default:
            break
        }
    }
    
    public func updateNetworkData(_ requests: [NetworkRequest]) {
        networkRequests = requests.sorted { $0.requestTime > $1.requestTime }
        
        // 네트워크 요청 개수 제한 (메모리 누수 방지)
        if networkRequests.count > 30 {
            networkRequests = Array(networkRequests.prefix(30))
        }
        
        PeriscopeLogger.log("Updating network data with \(networkRequests.count) requests")
        PeriscopeLogger.log("Current tab: \(tabSegmentedControl.selectedSegmentIndex) (0=Console, 1=Network, 2=Storage)")
        DispatchQueue.main.async { [weak self] in
            self?.networkTableView.reloadData()
            PeriscopeLogger.log("Network table view reloaded with \(self?.networkRequests.count ?? 0) items")
        }
    }
    
    public func updateStorageData(_ data: StorageData) {
        PeriscopeLogger.log("Storage data received:")
        PeriscopeLogger.log("  - localStorage: \(data.localStorage.count) items")
        PeriscopeLogger.log("  - sessionStorage: \(data.sessionStorage.count) items") 
        PeriscopeLogger.log("  - cookies: \(data.cookies.isEmpty ? "empty" : "has data")")
        
        storageData = data
        DispatchQueue.main.async { [weak self] in
            self?.storageTableView.reloadData()
            PeriscopeLogger.log("Storage table view reloaded")
        }
    }
    
    private func showNetworkRequestDetail(_ request: NetworkRequest) {
        let detailVC = NetworkRequestDetailViewController(request: request)
        let navController = UINavigationController(rootViewController: detailVC)
        
        // Find the parent view controller to present from
        var parentVC: UIViewController?
        var responder: UIResponder? = self
        while let nextResponder = responder?.next {
            if let viewController = nextResponder as? UIViewController {
                parentVC = viewController
                break
            }
            responder = nextResponder
        }
        
        parentVC?.present(navController, animated: true)
    }
    
    public func cleanupMemoryOnBackground() {
        // 백그라운드에서 메모리 정리
        if logs.count > 100 {
            logs = Array(logs.suffix(50))
            applyFilters()
        }
        
        if networkRequests.count > 20 {
            networkRequests = Array(networkRequests.prefix(10))
        }
        
        // Storage 데이터는 최신 상태만 유지
        storageData = nil
    }
}

// MARK: - UITableViewDataSource & UITableViewDelegate

extension PeriscopeConsoleModal: UITableViewDataSource, UITableViewDelegate {
    
    public func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        switch tableView {
        case self.tableView:
            return filteredLogs.count
        case networkTableView:
            return networkRequests.count
        case storageTableView:
            let localCount = storageData?.localStorage.count ?? 0
            let sessionCount = storageData?.sessionStorage.count ?? 0 
            let cookieCount = storageData?.parsedCookies.count ?? 0
            let rowCount = section == 0 ? localCount : section == 1 ? sessionCount : cookieCount
            PeriscopeLogger.log("Storage tableView rows for section \(section): \(rowCount)")
            PeriscopeLogger.log("Storage data details: localStorage=\(localCount), sessionStorage=\(sessionCount), cookies=\(cookieCount)")
            if let data = storageData {
                PeriscopeLogger.log("Current localStorage: \(data.localStorage)")
                PeriscopeLogger.log("Current sessionStorage: \(data.sessionStorage)")
                PeriscopeLogger.log("Current cookies: \(data.cookies)")
            } else {
                PeriscopeLogger.warning("No storage data available")
            }
            
            // 빈 상태일 때도 최소 1개 행 표시 (메시지용)
            return max(rowCount, rowCount == 0 ? 1 : rowCount)
        default:
            return 0
        }
    }
    
    public func numberOfSections(in tableView: UITableView) -> Int {
        if tableView == storageTableView {
            return 3 // localStorage, sessionStorage, cookies
        }
        return 1
    }
    
    public func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        if tableView == storageTableView {
            switch section {
            case 0: return "Local Storage"
            case 1: return "Session Storage"
            case 2: return "Cookies"
            default: return nil
            }
        }
        return nil
    }
    
    public func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        switch tableView {
        case self.tableView:
            let cell = tableView.dequeueReusableCell(withIdentifier: "ConsoleLogCell", for: indexPath) as! ConsoleLogCell
            let log = filteredLogs[indexPath.row]
            cell.configure(with: log)
            return cell
            
        case networkTableView:
            let cell = tableView.dequeueReusableCell(withIdentifier: "NetworkRequestCell", for: indexPath) as! NetworkRequestCell
            let request = networkRequests[indexPath.row]
            cell.configure(with: request)
            return cell
            
        case storageTableView:
            let cell = tableView.dequeueReusableCell(withIdentifier: "StorageItemCell", for: indexPath) as! StorageItemCell
            if indexPath.section == 0 {
                let items = Array(storageData?.localStorage ?? [:]).sorted { $0.key < $1.key }
                if indexPath.row < items.count {
                    cell.configure(key: items[indexPath.row].key, value: items[indexPath.row].value)
                } else {
                    cell.configure(key: "No localStorage data", value: "Set some data using localStorage.setItem()")
                }
            } else if indexPath.section == 1 {
                let items = Array(storageData?.sessionStorage ?? [:]).sorted { $0.key < $1.key }
                if indexPath.row < items.count {
                    cell.configure(key: items[indexPath.row].key, value: items[indexPath.row].value)
                } else {
                    cell.configure(key: "No sessionStorage data", value: "Set some data using sessionStorage.setItem()")
                }
            } else if indexPath.section == 2 {
                let cookies = storageData?.parsedCookies ?? []
                if indexPath.row < cookies.count {
                    cell.configure(key: cookies[indexPath.row]["name"] ?? "", value: cookies[indexPath.row]["value"] ?? "")
                } else {
                    cell.configure(key: "No cookies", value: "Set cookies using document.cookie")
                }
            }
            return cell
            
        default:
            return UITableViewCell()
        }
    }
    
    public func tableView(_ tableView: UITableView, estimatedHeightForRowAt indexPath: IndexPath) -> CGFloat {
        return 60
    }
    
    public func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        return UITableView.automaticDimension
    }
    
    public func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        
        // Only handle network table row selection
        if tableView == networkTableView {
            let request = networkRequests[indexPath.row]
            showNetworkRequestDetail(request)
        }
    }
}

// MARK: - ConsoleLogCell

private class ConsoleLogCell: UITableViewCell {
    
    private let levelLabel = UILabel()
    private let timeLabel = UILabel()
    private let messageLabel = UILabel()
    private let sourceLabel = UILabel()
    
    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        setupUI()
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupUI()
    }
    
    private func setupUI() {
        selectionStyle = .none
        
        levelLabel.font = UIFont.systemFont(ofSize: 12, weight: .medium)
        levelLabel.translatesAutoresizingMaskIntoConstraints = false
        
        timeLabel.font = UIFont.monospacedSystemFont(ofSize: 10, weight: .regular)
        timeLabel.textColor = UIColor.secondaryLabel
        timeLabel.translatesAutoresizingMaskIntoConstraints = false
        
        messageLabel.font = UIFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        messageLabel.numberOfLines = 0
        messageLabel.translatesAutoresizingMaskIntoConstraints = false
        
        sourceLabel.font = UIFont.systemFont(ofSize: 10, weight: .regular)
        sourceLabel.textColor = UIColor.tertiaryLabel
        sourceLabel.translatesAutoresizingMaskIntoConstraints = false
        
        contentView.addSubview(levelLabel)
        contentView.addSubview(timeLabel)
        contentView.addSubview(messageLabel)
        contentView.addSubview(sourceLabel)
        
        NSLayoutConstraint.activate([
            levelLabel.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 8),
            levelLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            levelLabel.widthAnchor.constraint(equalToConstant: 60),
            
            timeLabel.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 8),
            timeLabel.leadingAnchor.constraint(equalTo: levelLabel.trailingAnchor, constant: 8),
            timeLabel.widthAnchor.constraint(equalToConstant: 80),
            
            messageLabel.topAnchor.constraint(equalTo: levelLabel.bottomAnchor, constant: 4),
            messageLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            messageLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            
            sourceLabel.topAnchor.constraint(equalTo: messageLabel.bottomAnchor, constant: 2),
            sourceLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            sourceLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            sourceLabel.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -8)
        ])
    }
    
    override func prepareForReuse() {
        super.prepareForReuse()
        levelLabel.text = nil
        timeLabel.text = nil
        messageLabel.text = nil
        messageLabel.textColor = UIColor.label
        sourceLabel.text = nil
        sourceLabel.isHidden = true
    }
    
    func configure(with log: ConsoleLog) {
        levelLabel.text = log.level.emoji
        timeLabel.text = log.formattedTimestamp
        messageLabel.text = log.message
        sourceLabel.text = log.source
        sourceLabel.isHidden = log.source == nil
        
        // 레벨에 따른 색상 설정
        switch log.level {
        case .log:
            messageLabel.textColor = UIColor.label
        case .info:
            messageLabel.textColor = UIColor.systemBlue
        case .warn:
            messageLabel.textColor = UIColor.systemOrange
        case .error:
            messageLabel.textColor = UIColor.systemRed
        case .debug:
            messageLabel.textColor = UIColor.systemPurple
        }
    }
}

// MARK: - NetworkRequestCell

private class NetworkRequestCell: UITableViewCell {
    
    private let methodLabel = UILabel()
    private let urlLabel = UILabel()
    private let statusLabel = UILabel()
    private let durationLabel = UILabel()
    private let sizeLabel = UILabel()
    
    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        setupUI()
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupUI()
    }
    
    private func setupUI() {
        selectionStyle = .none
        
        methodLabel.font = UIFont.systemFont(ofSize: 12, weight: .semibold)
        methodLabel.translatesAutoresizingMaskIntoConstraints = false
        
        urlLabel.font = UIFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        urlLabel.numberOfLines = 2
        urlLabel.translatesAutoresizingMaskIntoConstraints = false
        
        statusLabel.font = UIFont.systemFont(ofSize: 12, weight: .medium)
        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        
        durationLabel.font = UIFont.monospacedSystemFont(ofSize: 10, weight: .regular)
        durationLabel.textColor = UIColor.secondaryLabel
        durationLabel.translatesAutoresizingMaskIntoConstraints = false
        
        sizeLabel.font = UIFont.monospacedSystemFont(ofSize: 10, weight: .regular)
        sizeLabel.textColor = UIColor.secondaryLabel
        sizeLabel.translatesAutoresizingMaskIntoConstraints = false
        
        contentView.addSubview(methodLabel)
        contentView.addSubview(urlLabel)
        contentView.addSubview(statusLabel)
        contentView.addSubview(durationLabel)
        contentView.addSubview(sizeLabel)
        
        NSLayoutConstraint.activate([
            methodLabel.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 8),
            methodLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            methodLabel.widthAnchor.constraint(equalToConstant: 60),
            
            statusLabel.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 8),
            statusLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            
            sizeLabel.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 8),
            sizeLabel.trailingAnchor.constraint(equalTo: statusLabel.leadingAnchor, constant: -8),
            
            durationLabel.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 8),
            durationLabel.trailingAnchor.constraint(equalTo: sizeLabel.leadingAnchor, constant: -8),
            
            urlLabel.topAnchor.constraint(equalTo: methodLabel.bottomAnchor, constant: 4),
            urlLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            urlLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            urlLabel.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -8)
        ])
    }
    
    override func prepareForReuse() {
        super.prepareForReuse()
        methodLabel.text = nil
        methodLabel.textColor = UIColor.label
        urlLabel.text = nil
        statusLabel.text = nil
        statusLabel.textColor = UIColor.label
        durationLabel.text = nil
        sizeLabel.text = nil
    }
    
    func configure(with request: NetworkRequest) {
        methodLabel.text = request.method
        urlLabel.text = request.url
        durationLabel.text = request.formattedDuration
        sizeLabel.text = request.formattedSize
        
        // Method color
        switch request.method {
        case "GET":
            methodLabel.textColor = UIColor.systemGreen
        case "POST":
            methodLabel.textColor = UIColor.systemBlue
        case "PUT", "PATCH":
            methodLabel.textColor = UIColor.systemOrange
        case "DELETE":
            methodLabel.textColor = UIColor.systemRed
        default:
            methodLabel.textColor = UIColor.label
        }
        
        // Status
        switch request.status {
        case .pending:
            statusLabel.text = "⏳"
        case .success:
            if let code = request.statusCode {
                statusLabel.text = "\(code)"
                if code >= 200 && code < 300 {
                    statusLabel.textColor = UIColor.systemGreen
                } else if code >= 300 && code < 400 {
                    statusLabel.textColor = UIColor.systemOrange
                } else {
                    statusLabel.textColor = UIColor.systemRed
                }
            } else {
                statusLabel.text = "✓"
                statusLabel.textColor = UIColor.systemGreen
            }
        case .error:
            statusLabel.text = "✗"
            statusLabel.textColor = UIColor.systemRed
        }
    }
}

// MARK: - StorageItemCell

private class StorageItemCell: UITableViewCell {
    
    private let keyLabel = UILabel()
    private let valueLabel = UILabel()
    
    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        setupUI()
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupUI()
    }
    
    private func setupUI() {
        selectionStyle = .none
        
        keyLabel.font = UIFont.systemFont(ofSize: 13, weight: .medium)
        keyLabel.textColor = UIColor.systemBlue
        keyLabel.translatesAutoresizingMaskIntoConstraints = false
        
        valueLabel.font = UIFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        valueLabel.textColor = UIColor.label
        valueLabel.numberOfLines = 0
        valueLabel.translatesAutoresizingMaskIntoConstraints = false
        
        contentView.addSubview(keyLabel)
        contentView.addSubview(valueLabel)
        
        NSLayoutConstraint.activate([
            keyLabel.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 8),
            keyLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            keyLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            
            valueLabel.topAnchor.constraint(equalTo: keyLabel.bottomAnchor, constant: 4),
            valueLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            valueLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            valueLabel.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -8)
        ])
    }
    
    override func prepareForReuse() {
        super.prepareForReuse()
        keyLabel.text = nil
        valueLabel.text = nil
    }
    
    func configure(key: String, value: String) {
        keyLabel.text = key
        valueLabel.text = value
    }
}
