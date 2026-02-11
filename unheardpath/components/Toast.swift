import SwiftUI

// MARK: - Activity Update Banner Component
/// A banner for activity updates in liveUpdateStack.
///
/// **Dismiss behavior by toast type:**
/// - "info" toasts represent in-progress operations and persist with a spinner until replaced
///   by the next toast or dismissed externally (e.g., on `stop` event). A 60-second stale guard
///   auto-dismisses if no new event arrives (safety net for backend errors).
/// - All other types (success, error, warning, etc.) auto-dismiss after 4 seconds.
///
/// When a new toast arrives, SwiftUI removes this view (onDisappear cancels any pending timer).
/// Uses `onToastDimiss` (separate from the message bubble's `onDismiss`).
struct ToastView: View {
    let toastData: ToastData
    let onToastDimiss: () -> Void
    @State private var dismissTask: Task<Void, Never>?
    
    /// Whether this toast represents an in-progress operation that should persist until
    /// replaced or externally dismissed (e.g., by a `stop` SSE event).
    private var isInProgress: Bool {
        guard let type = toastData.type?.lowercased() else { return false }
        switch type {
        case "info", "information", "search", "search web", "update", "refresh", "location", "gps":
            return true
        default:
            return false
        }
    }
    
    /// Maps activity update type to SF Symbol icon name
    private var iconName: String {
        guard let type = toastData.type else {
            return "bell.fill" // Default icon for null type
        }
        
        switch type.lowercased() {
        case "info", "information":
            return "info.circle.fill"
        case "search", "search web":
            return "magnifyingglass"
        case "success", "completed":
            return "checkmark.circle.fill"
        case "warning", "alert":
            return "exclamationmark.triangle.fill"
        case "error", "failure":
            return "xmark.circle.fill"
        case "location", "gps":
            return "location.fill"
        case "journey", "trip":
            return "signpost.right.and.left.fill"
        case "message", "chat":
            return "message.fill"
        case "update", "refresh":
            return "arrow.clockwise.circle.fill"
        default:
            return "bell.fill" // Default icon for unknown types
        }
    }
    
    // The banner content itself
    private var bannerContent: some View {
        HStack(spacing: 12) {
            if isInProgress {
                // Spinner for in-progress toasts
                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle(tint: .primary))
                    .frame(width: 24, height: 24)
            } else {
                // Static icon for terminal-state toasts
                Image(systemName: iconName)
                    .font(.title3)
                    .foregroundColor(.primary)
                    .frame(width: 24, height: 24)
            }
            
            // Activity update message
            Text(toastData.message)
                .bodyText()
                .foregroundColor(Color("onBkgTextColor20"))
                .lineLimit(2)
                .multilineTextAlignment(.leading)
        }
        .padding(.horizontal, 16)  // Inner padding: space between content and background
        .padding(.vertical, 12)     // Inner padding: space between content and background
        .background(
            Color("AppBkgColor")
                .opacity(0.95)
                .cornerRadius(Spacing.current.spaceS)
                .shadow(color: Color.black.opacity(0.1), radius: 8, x: 0, y: 2)
        )
    }
    
    var body: some View {
        bannerContent
            .transition(.move(edge: .bottom).combined(with: .opacity))
            .onAppear {
                startDismissTimer()
            }
            .onDisappear {
                // Cancel dismiss task when view disappears (e.g., when new toast arrives or
                // externally dismissed via stop event)
                dismissTask?.cancel()
            }
    }
    
    /// Starts the appropriate dismiss timer based on toast type.
    /// - In-progress toasts: 60-second stale guard (safety net if backend never sends stop)
    /// - Terminal toasts: 4-second auto-dismiss
    private func startDismissTimer() {
        let timeout: UInt64 = isInProgress
            ? 60_000_000_000  // 60 seconds — stale guard for in-progress toasts
            : 4_000_000_000   // 4 seconds — auto-dismiss for terminal toasts
        
        dismissTask = Task {
            try? await Task.sleep(nanoseconds: timeout)
            await MainActor.run {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                    onToastDimiss()
                }
            }
        }
    }
}

// MARK: - Preview: Simulated SSE Toast Stream

/// Wrapper that drives a ToastManager through a scripted sequence of SSE-style
/// toast events, each arriving after a configurable delay.
private struct ToastSSEPreviewWrapper: View {
    @StateObject private var toastManager = ToastManager()
    @State private var eventLog: [String] = []
    @State private var isRunning = false

    /// Each step: (delay in seconds before firing, toast data or nil for dismiss)
    private let sseScript: [(delay: Double, toast: ToastData?)] = [
        // 1) Kick off with a location lookup (in-progress spinner)
        (delay: 1.0,  toast: ToastData(type: "location", message: "Detecting your location…")),
        // 2) Switch to a search (still in-progress)
        (delay: 2.5,  toast: ToastData(type: "search", message: "Searching nearby landmarks…")),
        // 3) Quick info update
        (delay: 3.0,  toast: ToastData(type: "info", message: "Fetching cultural context…")),
        // 4) Another search after a short pause
        (delay: 1.5,  toast: ToastData(type: "search web", message: "Looking up opening hours…")),
        // 5) Refresh/update step
        (delay: 2.0,  toast: ToastData(type: "update", message: "Refreshing journey data…")),
        // 6) Success — terminal toast, auto-dismisses after 4s
        (delay: 3.5,  toast: ToastData(type: "success", message: "Journey ready! Tap to start.")),
        // 7) Wait, then show a warning
        (delay: 5.0,  toast: ToastData(type: "warning", message: "Slow network detected.")),
        // 8) Error example
        (delay: 5.0,  toast: ToastData(type: "error", message: "Failed to load audio guide.")),
        // 9) Final dismiss (simulates SSE stop event)
        (delay: 5.0,  toast: nil),
    ]

    var body: some View {
        VStack(spacing: 0) {
            // Event log — scrollable history of what arrived
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 6) {
                        ForEach(Array(eventLog.enumerated()), id: \.offset) { index, entry in
                            Text(entry)
                                .font(.system(size: 12, design: .monospaced))
                                .foregroundColor(.secondary)
                                .id(index)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                }
                .onChange(of: eventLog.count) { _ in
                    if let last = eventLog.indices.last {
                        withAnimation {
                            proxy.scrollTo(last, anchor: .bottom)
                        }
                    }
                }
            }

            Spacer()

            // Toast display area
            if let toastData = toastManager.currentToastData {
                ToastView(
                    toastData: toastData,
                    onToastDimiss: {
                        toastManager.dismiss()
                    }
                )
                .padding(.horizontal, 16)
                .padding(.bottom, 8)
            }

            // Replay button
            Button(action: { runScript() }) {
                HStack(spacing: 6) {
                    Image(systemName: isRunning ? "arrow.trianglehead.2.counterclockwise" : "play.fill")
                    Text(isRunning ? "Running…" : "Replay SSE Stream")
                }
                .bodyText()
                .foregroundColor(Color("AppBkgColor"))
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                .background(isRunning ? Color.gray : Color.accentColor)
                .cornerRadius(Spacing.current.spaceXs)
            }
            .disabled(isRunning)
            .padding(.bottom, 24)
        }
        .background(Color("AppBkgColor"))
        .onAppear { runScript() }
    }

    private func runScript() {
        guard !isRunning else { return }
        isRunning = true
        eventLog = ["▶ SSE stream started"]
        toastManager.dismiss()

        Task {
            for (index, step) in sseScript.enumerated() {
                try? await Task.sleep(nanoseconds: UInt64(step.delay * 1_000_000_000))

                await MainActor.run {
                    if let toast = step.toast {
                        let label = "[\(String(format: "+%.1fs", step.delay))] toast → type: \(toast.type ?? "nil"), msg: \"\(toast.message)\""
                        eventLog.append(label)
                        toastManager.show(toast)
                    } else {
                        eventLog.append("[\(String(format: "+%.1fs", step.delay))] ■ stop (dismiss)")
                        toastManager.dismiss()
                    }
                }
            }

            await MainActor.run {
                eventLog.append("✓ Stream complete")
                isRunning = false
            }
        }
    }
}

#Preview("Toast — SSE Stream Simulation") {
    ToastSSEPreviewWrapper()
}

