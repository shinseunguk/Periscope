import UIKit
import WebKit
import Periscope

class ViewController: UIViewController {
    
    private let titleLabel: UILabel = {
        let label = UILabel()
        label.text = "Periscope UIKit Example"
        label.font = .systemFont(ofSize: 20, weight: .bold)
        label.textAlignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    private let webView: WKWebView = {
        let configuration = WKWebViewConfiguration()
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.translatesAutoresizingMaskIntoConstraints = false
        return webView
    }()
    
    private let buttonStackView: UIStackView = {
        let stackView = UIStackView()
        stackView.axis = .vertical
        stackView.spacing = 12
        stackView.distribution = .fillEqually
        stackView.translatesAutoresizingMaskIntoConstraints = false
        return stackView
    }()
    
    private let loadTestButton: UIButton = {
        let button = UIButton(type: .system)
        button.setTitle("Load Test Page", for: .normal)
        button.titleLabel?.font = .systemFont(ofSize: 16, weight: .medium)
        button.backgroundColor = .systemBlue
        button.setTitleColor(.white, for: .normal)
        button.layer.cornerRadius = 8
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }()
    
    private let enableDebugButton: UIButton = {
        let button = UIButton(type: .system)
        button.setTitle("Enable Debug", for: .normal)
        button.titleLabel?.font = .systemFont(ofSize: 16, weight: .medium)
        button.backgroundColor = .systemGreen
        button.setTitleColor(.white, for: .normal)
        button.layer.cornerRadius = 8
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }()
    
    private let disableDebugButton: UIButton = {
        let button = UIButton(type: .system)
        button.setTitle("Disable Debug", for: .normal)
        button.titleLabel?.font = .systemFont(ofSize: 16, weight: .medium)
        button.backgroundColor = .systemRed
        button.setTitleColor(.white, for: .normal)
        button.layer.cornerRadius = 8
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }()

    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        setupConstraints()
        setupActions()
        setupPeriscope()
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        
        // 앱 시작시 자동으로 테스트 페이지 로드
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            self.webView.loadTestHTML()
        }
    }
    
    private func setupUI() {
        view.backgroundColor = .systemBackground
        navigationItem.title = "Periscope UIKit"
        
        view.addSubview(titleLabel)
        view.addSubview(webView)
        view.addSubview(buttonStackView)
        
        buttonStackView.addArrangedSubview(loadTestButton)
        buttonStackView.addArrangedSubview(enableDebugButton)
        buttonStackView.addArrangedSubview(disableDebugButton)
    }
    
    private func setupConstraints() {
        NSLayoutConstraint.activate([
            titleLabel.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 20),
            titleLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            titleLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            
            webView.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 20),
            webView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            webView.heightAnchor.constraint(equalTo: view.heightAnchor, multiplier: 0.6),
            
            buttonStackView.topAnchor.constraint(equalTo: webView.bottomAnchor, constant: 20),
            buttonStackView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            buttonStackView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            buttonStackView.bottomAnchor.constraint(lessThanOrEqualTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -20),
            buttonStackView.heightAnchor.constraint(equalToConstant: 140)
        ])
    }
    
    private func setupActions() {
        loadTestButton.addTarget(self, action: #selector(loadTestButtonTapped), for: .touchUpInside)
        enableDebugButton.addTarget(self, action: #selector(enableDebugButtonTapped), for: .touchUpInside)
        disableDebugButton.addTarget(self, action: #selector(disableDebugButtonTapped), for: .touchUpInside)
    }
    
    private func setupPeriscope() {
        // Periscope 디버거 설정
        PeriscopeDebugger.shared.delegate = self
    }
    
    @objc private func loadTestButtonTapped() {
        webView.loadTestHTML()
        animateButton(loadTestButton)
    }
    
    @objc private func enableDebugButtonTapped() {
        webView.enablePeriscope()
        
        enableDebugButton.backgroundColor = .systemGray
        enableDebugButton.isEnabled = false
        disableDebugButton.backgroundColor = .systemRed
        disableDebugButton.isEnabled = true
        
        animateButton(enableDebugButton)
    }
    
    @objc private func disableDebugButtonTapped() {
        webView.disablePeriscope()
        
        enableDebugButton.backgroundColor = .systemGreen
        enableDebugButton.isEnabled = true
        disableDebugButton.backgroundColor = .systemGray
        disableDebugButton.isEnabled = false
        
        animateButton(disableDebugButton)
    }
    
    private func animateButton(_ button: UIButton) {
        UIView.animate(withDuration: 0.1, animations: {
            button.transform = CGAffineTransform(scaleX: 0.95, y: 0.95)
        }) { _ in
            UIView.animate(withDuration: 0.1) {
                button.transform = .identity
            }
        }
    }
}

// MARK: - PeriscopeDebuggerDelegate

extension ViewController: PeriscopeDebuggerDelegate {
    func periscopeDebugger(_ debugger: PeriscopeDebugger, didReceiveLog log: ConsoleLog) {
        print("📱 Native received log: [\(log.level.rawValue)] \(log.message)")
    }
    
    func periscopeDebuggerDidToggleVisibility(_ debugger: PeriscopeDebugger, isVisible: Bool) {
        print("📱 Console modal is now: \(isVisible ? "visible" : "hidden")")
    }
}