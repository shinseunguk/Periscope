import UIKit

public class PeriscopeFloatingButton: UIButton {
    
    private let shadowLayer = CAShapeLayer()
    private var onTap: (() -> Void)?
    
    public init(onTap: @escaping () -> Void) {
        self.onTap = onTap
        super.init(frame: .zero)
        setupUI()
        setupGesture()
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupUI()
        setupGesture()
    }
    
    private func setupUI() {
        // 기본 스타일 설정
        backgroundColor = UIColor.systemBlue
        layer.cornerRadius = 30
        layer.masksToBounds = false
        
        // 그림자 설정
        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOffset = CGSize(width: 0, height: 4)
        layer.shadowRadius = 8
        layer.shadowOpacity = 0.3
        
        // 아이콘 설정
        let bugIcon = createBugIcon()
        setImage(bugIcon, for: .normal)
        imageView?.contentMode = .scaleAspectFit
        imageView?.tintColor = .white
        
        // 애니메이션 효과
        addTarget(self, action: #selector(buttonPressed), for: .touchDown)
        addTarget(self, action: #selector(buttonReleased), for: [.touchUpInside, .touchUpOutside, .touchCancel])
    }
    
    private func setupGesture() {
        addTarget(self, action: #selector(buttonTapped), for: .touchUpInside)
    }
    
    private func createBugIcon() -> UIImage? {
        let size = CGSize(width: 24, height: 24)
        let renderer = UIGraphicsImageRenderer(size: size)
        
        return renderer.image { context in
            let rect = CGRect(origin: .zero, size: size)
            
            // 벌레 모양 그리기
            let path = UIBezierPath()
            
            // 몸통
            let bodyRect = CGRect(x: 8, y: 6, width: 8, height: 12)
            path.append(UIBezierPath(roundedRect: bodyRect, cornerRadius: 3))
            
            // 더듬이
            path.move(to: CGPoint(x: 10, y: 6))
            path.addLine(to: CGPoint(x: 8, y: 2))
            path.move(to: CGPoint(x: 14, y: 6))
            path.addLine(to: CGPoint(x: 16, y: 2))
            
            // 다리
            for i in 0...2 {
                let y = 8 + (i * 3)
                // 왼쪽 다리
                path.move(to: CGPoint(x: 8, y: y))
                path.addLine(to: CGPoint(x: 4, y: y + 1))
                // 오른쪽 다리  
                path.move(to: CGPoint(x: 16, y: y))
                path.addLine(to: CGPoint(x: 20, y: y + 1))
            }
            
            UIColor.white.setStroke()
            path.lineWidth = 1.5
            path.lineCapStyle = .round
            path.stroke()
            
            UIColor.white.setFill()
            UIBezierPath(roundedRect: bodyRect, cornerRadius: 3).fill()
        }
    }
    
    @objc private func buttonPressed() {
        UIView.animate(withDuration: 0.1) {
            self.transform = CGAffineTransform(scaleX: 0.9, y: 0.9)
        }
    }
    
    @objc private func buttonReleased() {
        UIView.animate(withDuration: 0.1) {
            self.transform = .identity
        }
    }
    
    @objc private func buttonTapped() {
        // 햅틱 피드백
        let impactGenerator = UIImpactFeedbackGenerator(style: .medium)
        impactGenerator.impactOccurred()
        
        // 콜백 실행
        onTap?()
    }
    
    // 드래그 가능하게 만들기
    public override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first,
              let superview = superview else { return }
        
        let location = touch.location(in: superview)
        let previousLocation = touch.previousLocation(in: superview)
        
        var newCenter = center
        newCenter.x += location.x - previousLocation.x
        newCenter.y += location.y - previousLocation.y
        
        // 화면 경계 내에서만 이동 가능
        let buttonRadius: CGFloat = 30
        newCenter.x = max(buttonRadius, min(superview.bounds.width - buttonRadius, newCenter.x))
        newCenter.y = max(buttonRadius, min(superview.bounds.height - buttonRadius, newCenter.y))
        
        center = newCenter
    }
}

// MARK: - Animation Extensions

extension PeriscopeFloatingButton {
    
    public func pulse() {
        let pulseAnimation = CABasicAnimation(keyPath: "transform.scale")
        pulseAnimation.duration = 0.6
        pulseAnimation.fromValue = 1.0
        pulseAnimation.toValue = 1.1
        pulseAnimation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        pulseAnimation.autoreverses = true
        pulseAnimation.repeatCount = 3
        
        layer.add(pulseAnimation, forKey: "pulse")
    }
    
    public func shake() {
        let shakeAnimation = CABasicAnimation(keyPath: "transform.rotation")
        shakeAnimation.duration = 0.1
        shakeAnimation.repeatCount = 3
        shakeAnimation.autoreverses = true
        shakeAnimation.fromValue = -0.1
        shakeAnimation.toValue = 0.1
        
        layer.add(shakeAnimation, forKey: "shake")
    }
}