import UIKit

public class NetworkRequestDetailViewController: UIViewController {
    
    private let request: NetworkRequest
    private var scrollView: UIScrollView!
    private var contentView: UIView!
    
    public init(request: NetworkRequest) {
        self.request = request
        super.init(nibName: nil, bundle: nil)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    public override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        populateData()
    }
    
    private func setupUI() {
        view.backgroundColor = UIColor.systemBackground
        
        // Navigation
        title = "Request Details"
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .done,
            target: self,
            action: #selector(closeButtonTapped)
        )
        
        // Scroll view
        scrollView = UIScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scrollView)
        
        contentView = UIView()
        contentView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(contentView)
        
        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            
            contentView.topAnchor.constraint(equalTo: scrollView.topAnchor),
            contentView.leadingAnchor.constraint(equalTo: scrollView.leadingAnchor),
            contentView.trailingAnchor.constraint(equalTo: scrollView.trailingAnchor),
            contentView.bottomAnchor.constraint(equalTo: scrollView.bottomAnchor),
            contentView.widthAnchor.constraint(equalTo: scrollView.widthAnchor)
        ])
    }
    
    private func populateData() {
        var yPosition: CGFloat = 20
        
        // Request section
        let requestSection = createSection(title: "Request", at: &yPosition)
        contentView.addSubview(requestSection)
        
        addField(title: "URL", value: request.url, to: requestSection, at: &yPosition)
        addField(title: "Method", value: request.method, to: requestSection, at: &yPosition)
        addField(title: "Time", value: DateFormatter.localizedString(from: request.requestTime, dateStyle: .none, timeStyle: .medium), to: requestSection, at: &yPosition)
        
        if let headers = request.headers, !headers.isEmpty {
            addField(title: "Request Headers", value: formatHeaders(headers), to: requestSection, at: &yPosition)
        }
        
        yPosition += 30
        
        // Response section
        let responseSection = createSection(title: "Response", at: &yPosition)
        contentView.addSubview(responseSection)
        
        addField(title: "Status", value: getStatusText(), to: responseSection, at: &yPosition)
        addField(title: "Duration", value: request.formattedDuration, to: responseSection, at: &yPosition)
        addField(title: "Size", value: request.formattedSize, to: responseSection, at: &yPosition)
        
        if let responseHeaders = request.responseHeaders, !responseHeaders.isEmpty {
            addField(title: "Response Headers", value: formatHeaders(responseHeaders), to: responseSection, at: &yPosition)
        }
        
        if let error = request.error {
            addField(title: "Error", value: error, to: responseSection, at: &yPosition)
        }
        
        if let body = request.responseBody, !body.isEmpty {
            addField(title: "Response Body", value: body, to: responseSection, at: &yPosition)
        }
        
        // Set content height
        NSLayoutConstraint.activate([
            contentView.heightAnchor.constraint(equalToConstant: yPosition + 20)
        ])
    }
    
    private func createSection(title: String, at yPosition: inout CGFloat) -> UIView {
        let sectionView = UIView()
        sectionView.translatesAutoresizingMaskIntoConstraints = false
        sectionView.backgroundColor = UIColor.systemGray6
        sectionView.layer.cornerRadius = 8
        
        let titleLabel = UILabel()
        titleLabel.text = title
        titleLabel.font = UIFont.boldSystemFont(ofSize: 18)
        titleLabel.textColor = UIColor.label
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        
        sectionView.addSubview(titleLabel)
        
        NSLayoutConstraint.activate([
            sectionView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: yPosition),
            sectionView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            sectionView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            
            titleLabel.topAnchor.constraint(equalTo: sectionView.topAnchor, constant: 12),
            titleLabel.leadingAnchor.constraint(equalTo: sectionView.leadingAnchor, constant: 16),
            titleLabel.trailingAnchor.constraint(equalTo: sectionView.trailingAnchor, constant: -16)
        ])
        
        yPosition += 50
        return sectionView
    }
    
    private func addField(title: String, value: String, to sectionView: UIView, at yPosition: inout CGFloat) {
        let titleLabel = UILabel()
        titleLabel.text = title + ":"
        titleLabel.font = UIFont.systemFont(ofSize: 14, weight: .medium)
        titleLabel.textColor = UIColor.secondaryLabel
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        
        let valueLabel = UILabel()
        valueLabel.text = value
        valueLabel.font = UIFont.monospacedSystemFont(ofSize: 13, weight: .regular)
        valueLabel.textColor = UIColor.label
        valueLabel.numberOfLines = 0
        valueLabel.translatesAutoresizingMaskIntoConstraints = false
        
        sectionView.addSubview(titleLabel)
        sectionView.addSubview(valueLabel)
        
        NSLayoutConstraint.activate([
            titleLabel.topAnchor.constraint(equalTo: sectionView.topAnchor, constant: yPosition - 30),
            titleLabel.leadingAnchor.constraint(equalTo: sectionView.leadingAnchor, constant: 16),
            titleLabel.trailingAnchor.constraint(equalTo: sectionView.trailingAnchor, constant: -16),
            
            valueLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 4),
            valueLabel.leadingAnchor.constraint(equalTo: sectionView.leadingAnchor, constant: 16),
            valueLabel.trailingAnchor.constraint(equalTo: sectionView.trailingAnchor, constant: -16)
        ])
        
        // Calculate height for multi-line text
        let maxWidth = view.frame.width - 64 // 16 + 16 + 16 + 16 for margins
        let estimatedHeight = value.heightWithConstrainedWidth(width: maxWidth, font: valueLabel.font)
        yPosition += 24 + estimatedHeight + 16 // title height + value height + spacing
        
        // Update section height
        if let lastConstraint = sectionView.constraints.last(where: { $0.firstAttribute == .height }) {
            sectionView.removeConstraint(lastConstraint)
        }
        
        NSLayoutConstraint.activate([
            sectionView.heightAnchor.constraint(equalToConstant: yPosition - 30)
        ])
    }
    
    private func getStatusText() -> String {
        switch request.status {
        case .pending:
            return "Pending ⏳"
        case .success:
            if let code = request.statusCode {
                return "\(code) \(HTTPURLResponse.localizedString(forStatusCode: code))"
            } else {
                return "Success ✓"
            }
        case .error:
            return "Error ✗"
        }
    }
    
    private func formatHeaders(_ headers: [String: String]) -> String {
        return headers.map { "\($0.key): \($0.value)" }.joined(separator: "\n")
    }
    
    @objc private func closeButtonTapped() {
        dismiss(animated: true)
    }
}

extension String {
    func heightWithConstrainedWidth(width: CGFloat, font: UIFont) -> CGFloat {
        let constraintRect = CGSize(width: width, height: .greatestFiniteMagnitude)
        let boundingBox = self.boundingRect(
            with: constraintRect,
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: [.font: font],
            context: nil
        )
        return ceil(boundingBox.height)
    }
}