import SwiftUI
import Periscope

struct ContentView: View {
    @State private var resultText = "Press the button to test"
    @State private var isButtonPressed = false
    
    var body: some View {
        NavigationView {
            VStack(spacing: 40) {
                Text("Periscope SwiftUI Example")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                    .multilineTextAlignment(.center)
                    .padding(.top, 40)
                
                Spacer()
                
                Button(action: testPeriscope) {
                    Text("Test Periscope")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundColor(.white)
                        .frame(width: 200, height: 50)
                        .background(Color.blue)
                        .cornerRadius(8)
                        .scaleEffect(isButtonPressed ? 0.95 : 1.0)
                }
                .buttonStyle(PlainButtonStyle())
                
                Text(resultText)
                    .font(.system(size: 16))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
                    .animation(.easeInOut, value: resultText)
                
                Spacer()
            }
            .navigationTitle("Periscope SwiftUI")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
        }
    }
    
    private func testPeriscope() {
        // Button press animation
        withAnimation(.easeInOut(duration: 0.1)) {
            isButtonPressed = true
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            withAnimation(.easeInOut(duration: 0.1)) {
                isButtonPressed = false
            }
        }
        
        // TODO: Add Periscope functionality here
        let periscope = Periscope()
        resultText = periscope.test()
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}