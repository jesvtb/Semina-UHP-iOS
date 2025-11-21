//
//  unheardpathApp.swift
//  unheardpath
//
//  Created by Jessica Luo on 2025-09-09.
//

import SwiftUI

@main
struct unheardpathApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                .onOpenURL { url in
                    Task {
                        do {
                            try await supabase.auth.session(from: url)
                        } catch {
                            print("Error handling auth callback: \(error)")
                        }
                    }
                }
        }
    }
}
