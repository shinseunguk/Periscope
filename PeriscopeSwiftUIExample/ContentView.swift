import SwiftUI
import WebKit
import Periscope

struct ContentView: View {
    @State private var webViewCoordinator = WebViewCoordinator()
    @State private var isDebugEnabled = false
    
    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                Text("Periscope SwiftUI Example")
                    .font(.title)
                    .fontWeight(.bold)
                    .padding(.top)
                
                // WebView가 먼저 화면에 표시됨
                WebView(coordinator: webViewCoordinator)
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: 300)
                    .background(Color.gray.opacity(0.1))
                    .cornerRadius(8)
                    .padding(.horizontal)
                    .onAppear {
                        // 앱 시작시 자동으로 테스트 페이지 로드
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                            webViewCoordinator.loadTestPage()
                        }
                    }
                
                VStack(spacing: 12) {
                    Button("Load Test Page") {
                        webViewCoordinator.loadTestPage()
                    }
                    .buttonStyle(PeriscopeButtonStyle(color: .blue))
                    
                    Button(isDebugEnabled ? "Disable Debug" : "Enable Debug") {
                        if isDebugEnabled {
                            webViewCoordinator.disableDebug()
                        } else {
                            webViewCoordinator.enableDebug()
                        }
                        isDebugEnabled.toggle()
                    }
                    .buttonStyle(PeriscopeButtonStyle(color: isDebugEnabled ? .red : .green))
                }
                .padding(.horizontal)
                
                Spacer()
            }
            .navigationTitle("Periscope SwiftUI")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
        }
    }
}

// MARK: - WebView Wrapper for SwiftUI

struct WebView: UIViewRepresentable {
    let coordinator: WebViewCoordinator
    
    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        let webView = WKWebView(frame: .zero, configuration: configuration)
        coordinator.webView = webView
        
        // Setup Periscope debugger delegate
        PeriscopeDebugger.shared.delegate = coordinator
        
        return webView
    }
    
    func updateUIView(_ uiView: WKWebView, context: Context) {
        // No updates needed
    }
}

// MARK: - WebView Coordinator

class WebViewCoordinator: ObservableObject, PeriscopeDebuggerDelegate {
    var webView: WKWebView?
    
    func loadTestPage() {
        webView?.loadTestHTML()
    }
    
    func enableDebug() {
        webView?.enablePeriscope()
    }
    
    func disableDebug() {
        webView?.disablePeriscope()
    }
    
    // MARK: - PeriscopeDebuggerDelegate
    
    func periscopeDebugger(_ debugger: PeriscopeDebugger, didReceiveLog log: ConsoleLog) {
        print("📱 SwiftUI received log: [\(log.level.rawValue)] \(log.message)")
    }
    
    func periscopeDebuggerDidToggleVisibility(_ debugger: PeriscopeDebugger, isVisible: Bool) {
        print("📱 Console modal is now: \(isVisible ? "visible" : "hidden")")
    }
}

// MARK: - Custom Button Style

struct PeriscopeButtonStyle: ButtonStyle {
    let color: Color
    
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 16, weight: .medium))
            .foregroundColor(.white)
            .frame(width: 200, height: 44)
            .background(color)
            .cornerRadius(8)
            .scaleEffect(configuration.isPressed ? 0.95 : 1.0)
            .animation(.easeInOut(duration: 0.1), value: configuration.isPressed)
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}