import SwiftUI

struct Primary: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding()
            .background(configuration.isPressed ? Color("AccentColor") : Color("AccentColor"))
            .foregroundColor(.white)
            .cornerRadius(2)
            .scaleEffect(configuration.isPressed ? 0.95 : 1.0)
    }
}

#Preview {
    Button("Click me") {
        print("Button tapped")
    }
    .buttonStyle(Primary())
}
