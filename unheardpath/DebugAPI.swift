//
//  DebugAPIView.swift
//  unheardpath
//
//  Created by Jessica Luo on 2025-09-09.
//

import SwiftUI

// MARK: - Debug API Service Interaction Component
struct DebugAPIView: View {
    @StateObject private var apiService = APIService()
    @State private var responseText = "Ready to make API calls"
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var isSuccess = true

    var body: some View {
        ZStack {
            VStack(spacing: 16) {
                DebugHeaderView()
                TestButtonsView(
                    isLoading: isLoading,
                    iconForTest: iconForTest,
                    colorForTest: colorForTest,
                    runTest: runTest
                )
                
                LoadingIndicatorView(isLoading: isLoading)
                
                ResponseDisplayView(
                    responseText: responseText,
                    errorMessage: errorMessage,
                    isSuccess: isSuccess
                )
                
                Spacer()
            }
            .padding()
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .background(Color.orange.opacity(0.05))
        }
        .overlay(alignment: .topLeading) {
            BackButton(showBackground: true)
        }
        .navigationBarHidden(true)
    }
    
    // MARK: - Test Functions
    
    private func runTest(config: APITestConfig) async {
        isLoading = true
        errorMessage = nil
        
        let result = await APITestUtilities.runTest(config: config, apiService: apiService)
        responseText = result.response
        errorMessage = result.error
        isSuccess = result.success
        
        isLoading = false
    }
    
    // MARK: - Helper Functions
    
    private func iconForTest(_ name: String) -> String {
        switch name {
        case "Ollama": return "server.rack"
        case "Modal": return "cloud.fill"
        case "Request Building": return "wrench.and.screwdriver"
        case "JSON Request Body": return "doc.text"
        default: return "gear"
        }
    }
    
    private func colorForTest(_ name: String) -> Color {
        switch name {
        case "Ollama": return .blue
        case "Modal": return .purple
        case "Request Building": return .green
        case "JSON Request Body": return .orange
        default: return .gray
        }
    }
}

// MARK: - Debug Header View Component
struct DebugHeaderView: View {
    var body: some View {
        HStack {
            Image(systemName: "ladybug.fill")
                .foregroundColor(.orange)
            Text("Debug API Tests")
                .font(.headline)
            Spacer()
            Text("DEV ONLY")
                .font(.caption)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.orange.opacity(0.2))
                .cornerRadius(6)
        }
    }
}

// MARK: - Test Buttons View Component
struct TestButtonsView: View {
    let isLoading: Bool
    let iconForTest: (String) -> String
    let colorForTest: (String) -> Color
    let runTest: (APITestConfig) async -> Void
    
    var body: some View {
        VStack(spacing: 12) {
            ForEach(APITestUtilities.testConfigurations, id: \.name) { config in
                TestButton(
                    title: "Test \(config.name)",
                    icon: iconForTest(config.name),
                    color: colorForTest(config.name),
                    action: { await runTest(config) }
                )
            }
        }
        .disabled(isLoading)
    }
}

// MARK: - Loading Indicator View Component
struct LoadingIndicatorView: View {
    let isLoading: Bool
    
    var body: some View {
        if isLoading {
            HStack {
                ProgressView()
                    .scaleEffect(0.8)
                Text("Making API call...")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }
}

// MARK: - Response Display View Component
struct ResponseDisplayView: View {
    let responseText: String
    let errorMessage: String?
    let isSuccess: Bool
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                if !isSuccess, let errorMessage = errorMessage {
                    // Error state with red X icon
                    HStack(spacing: 8) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.red)
                            .font(.title2)
                        Text("Error: \(errorMessage)")
                            .font(.system(.caption, design: .monospaced))
                            .foregroundColor(.red)
                    }
                    .padding(8)
                    .background(Color.red.opacity(0.1))
                    .cornerRadius(6)
                } else {
                    // Success state with green checkmark icon
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                            .font(.title2)
                        Text(responseText)
                            .font(.system(.caption, design: .monospaced))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(8)
                    .background(Color.green.opacity(0.1))
                    .cornerRadius(6)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.green.opacity(0.1))
    }
}

// MARK: - Test Button Component
struct TestButton: View {
    let title: String
    let icon: String
    let color: Color
    let action: () async -> Void
    
    var body: some View {
        Button(action: { Task { await action() } }) {
            HStack {
                Image(systemName: icon)
                Text(title)
                    .fontWeight(.medium)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(color)
            .foregroundColor(.white)
            .cornerRadius(8)
        }
    }
}

// MARK: - Preview
#if DEBUG
#Preview {
    NavigationStack {
        DebugAPIView()
    }
}
#endif
