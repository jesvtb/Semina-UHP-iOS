import SwiftUI

// MARK: - Content View Builder
struct ContentViewBuilder: Identifiable {
    let id: UUID
    let builder: () -> AnyView
    
    init<Content: View>(id: UUID = UUID(), @ViewBuilder content: @escaping () -> Content) {
        self.id = id
        self.builder = {
            AnyView(content())
        }
    }
}

