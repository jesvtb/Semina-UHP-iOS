import SwiftUI

struct ChatDetailView: View {
    let messages: [String]
    
    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 8) {
                    ForEach(Array(messages.enumerated()), id: \.offset) { index, message in
                        Text(message)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                            .background(Color(.secondarySystemBackground))
                            .cornerRadius(16)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .id(index)
                    }
                }
                .padding(.top, 16)
                .padding(.bottom, 8) // extra space above input bar
            }
            .onChange(of: messages.count) { _ in
                withAnimation(.easeOut(duration: 0.25)) {
                    proxy.scrollTo(messages.indices.last, anchor: .bottom)
                }
            }
        }
    }
}

