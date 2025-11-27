//
//  Components.swift
//  unheardpath
//
//  Created by Jessica Luo on 2025-01-27.
//

import SwiftUI

// MARK: - Button Style System

/// Shared color themes for buttons
enum ButtonTheme {
    case primary
    case secondary
    case success
    case warning
    case danger
    
    var color: Color {
        switch self {
        case .primary: return .blue
        case .secondary: return .gray
        case .success: return .green
        case .warning: return .orange
        case .danger: return .red
        }
    }
}

/// Button size variants
enum ButtonSize {
    case small
    case medium
    case large
    
    var padding: EdgeInsets {
        switch self {
        case .small: return EdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12)
        case .medium: return EdgeInsets(top: 12, leading: 16, bottom: 12, trailing: 16)
        case .large: return EdgeInsets(top: 16, leading: 20, bottom: 16, trailing: 20)
        }
    }
    
    var font: Font {
        switch self {
        case .small: return .caption
        case .medium: return .body
        case .large: return .headline
        }
    }
    
    var iconSize: Font {
        switch self {
        case .small: return .caption
        case .medium: return .body
        case .large: return .title3
        }
    }
}

// MARK: - Reusable Button Components

/// Big Button - Full width, prominent style
struct BgButton: View {
    let label: String
    let icon: String?
    let theme: ButtonTheme
    let action: () -> Void
    
    init(
        label: String,
        icon: String? = nil,
        theme: ButtonTheme = .primary,
        action: @escaping () -> Void
    ) {
        self.label = label
        self.icon = icon
        self.theme = theme
        self.action = action
    }
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if let icon = icon {
                    Image(systemName: icon)
                        .font(ButtonSize.large.iconSize)
                }
                Text(label)
                    .font(ButtonSize.large.font)
                    .fontWeight(.semibold)
            }
            .frame(maxWidth: .infinity)
            .padding(ButtonSize.large.padding)
            .background(theme.color)
            .foregroundColor(.white)
            .cornerRadius(12)
        }
    }
}

/// Small Button - Compact, inline style
struct SmButton: View {
    let label: String
    let icon: String?
    let theme: ButtonTheme
    let action: () -> Void
    
    init(
        label: String,
        icon: String? = nil,
        theme: ButtonTheme = .primary,
        action: @escaping () -> Void
    ) {
        self.label = label
        self.icon = icon
        self.theme = theme
        self.action = action
    }
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                if let icon = icon {
                    Image(systemName: icon)
                        .font(ButtonSize.small.iconSize)
                }
                Text(label)
                    .font(ButtonSize.small.font)
                    .fontWeight(.medium)
            }
            .padding(ButtonSize.small.padding)
            .background(theme.color)
            .foregroundColor(.white)
            .cornerRadius(8)
        }
    }
}

/// Outlined Button - Border style with theme colors
struct OutlinedButton: View {
    let label: String
    let icon: String?
    let theme: ButtonTheme
    let size: ButtonSize
    let action: () -> Void
    
    init(
        label: String,
        icon: String? = nil,
        theme: ButtonTheme = .primary,
        size: ButtonSize = .medium,
        action: @escaping () -> Void
    ) {
        self.label = label
        self.icon = icon
        self.theme = theme
        self.size = size
        self.action = action
    }
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: size == .small ? 4 : 8) {
                if let icon = icon {
                    Image(systemName: icon)
                        .font(size.iconSize)
                }
                Text(label)
                    .font(size.font)
                    .fontWeight(size == .small ? .medium : .semibold)
            }
            .frame(maxWidth: size == .large ? .infinity : nil)
            .padding(size.padding)
            .foregroundColor(theme.color)
            .overlay(
                RoundedRectangle(cornerRadius: size == .small ? 8 : 12)
                    .stroke(theme.color, lineWidth: 2)
            )
        }
    }
}

// MARK: - Navigation Components

/// Back Button - Reusable back button component for navigation
struct BackButton: View {
    @Environment(\.dismiss) private var dismiss
    
    let showBackground: Bool
    let horizontalPadding: CGFloat
    
    init(
        showBackground: Bool = false,
        horizontalPadding: CGFloat = 20
    ) {
        self.showBackground = showBackground
        self.horizontalPadding = horizontalPadding
    }
    
    var body: some View {
        Button(action: {
            dismiss()
        }) {
            HStack(spacing: 8) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 16, weight: .semibold))
                Text("Back")
                    .font(.headline)
            }
            .foregroundColor(.white)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(
                Group {
                    if showBackground {
                        RoundedRectangle(cornerRadius: 10)
                            .fill(Color.black.opacity(0.4))
                    }
                }
            )
        }
        .padding(.horizontal, horizontalPadding)
        .padding(.top, 8)
    }
}

// MARK: - Preview Examples
#Preview("Button Components") {
    VStack(spacing: 20) {
        // Big Buttons
        VStack(spacing: 12) {
            BgButton(label: "Start Journey", icon: "play.circle.fill", theme: .success) {
                print("Start tapped")
            }
            
            BgButton(label: "Download", icon: "arrow.down.circle.fill", theme: .primary) {
                print("Download tapped")
            }
            
            BgButton(label: "Delete", theme: .danger) {
                print("Delete tapped")
            }
        }
        
        // Small Buttons
        HStack(spacing: 12) {
            SmButton(label: "Edit", icon: "pencil", theme: .secondary) {
                print("Edit tapped")
            }
            
            SmButton(label: "Save", icon: "checkmark", theme: .success) {
                print("Save tapped")
            }
        }
        
        // Outlined Buttons
        VStack(spacing: 12) {
            OutlinedButton(label: "Cancel", theme: .secondary, size: .large) {
                print("Cancel tapped")
            }
            
            HStack(spacing: 12) {
                OutlinedButton(label: "Skip", theme: .warning, size: .small) {
                    print("Skip tapped")
                }
                
                OutlinedButton(label: "Next", icon: "arrow.right", theme: .primary, size: .small) {
                    print("Next tapped")
                }
            }
        }
    }
    .padding()
}
