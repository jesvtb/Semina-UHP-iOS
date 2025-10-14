//
//  ContentView.swift
//  unheardpath
//
//  Created by Jessica Luo on 2025-09-09.
//

import SwiftUI

// MARK: - Content View
struct ContentView: View {
    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                // Main App Content
                VStack(spacing: 20) {
                    WelcomeHeaderView()
                    
                    NavigationLink(destination: AppleMapView()) {
                        HStack {
                            Image(systemName: "map")
                                .font(.title2)
                            Text("Apple Map")
                                .font(.headline)
                        }
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.blue)
                        .cornerRadius(12)
                    }
                    
                    NavigationLink(destination: MapboxMapView()) {
                        HStack {
                            Image(systemName: "map")
                                .font(.title2)
                            Text("Mapbox Map")
                                .font(.headline)
                        }
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.blue)
                        .cornerRadius(12)
                    }
                    
                    NavigationLink(destination: JourneyStart()) {
                        HStack {
                            Image(systemName: "play.circle")
                                .font(.title2)
                            Text("Journey Start")
                                .font(.headline)
                        }
                        .foregroundColor(.purple)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(Color.purple, lineWidth: 2)
                        )
                    }
                    
                    #if DEBUG
                    NavigationLink(destination: DebugAPIView()) {
                        HStack {
                            Image(systemName: "ladybug.fill")
                                .font(.title2)
                            Text("Debug API Tests")
                                .font(.headline)
                        }
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.orange)
                        .cornerRadius(12)
                    }
                    #endif
                }
                .padding()
                
                Spacer()
            }
            .navigationTitle("unheardpath")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

// MARK: - Welcome Header Component
struct WelcomeHeaderView: View {
    var body: some View {
        VStack(spacing: 8) {
            Text("Welcome to unheardpath")
                .font(.largeTitle)
                .fontWeight(.bold)
                .foregroundColor(.primary)
            
            Text("Your main app content goes here")
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
    }
}


#Preview {
    ContentView()
}
