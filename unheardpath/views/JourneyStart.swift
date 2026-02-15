//
//  JourneyStart.swift
//  unheardpath
//
//  Created by Jessica Luo on 2025-01-27.
//

import SwiftUI

struct JourneyStart: View {
    @Environment(\.dismiss) private var dismiss
    
    // Istanbul map image URL
    let backgroundImageURL = "https://lp-cms-production.imgix.net/2025-02/shutterstock2500020869.jpg?auto=format,compress&q=72&w=1440&h=810&fit=crop"
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Layer 1: Fixed background map loaded from URL
                AsyncImage(url: URL(string: backgroundImageURL)) { image in
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } placeholder: {
                    // Placeholder while loading
                    Rectangle()
                        .fill(Color.gray.opacity(0.3))
                        .overlay(
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        )
                }
                .frame(width: geometry.size.width, height: geometry.size.height)
                .clipped()
                
                // Layer 2: Scrollable content layer
                ScrollView {
                    VStack(spacing: 0) {
                        // Top navigation and route info
                        
                        
                        // CoverContent container
                        CoverContentSection(geometry: geometry)
                        
                        // Main body content
                        HistoricalBackgroundSection()
                    }
                    .frame(minHeight: geometry.size.height)
                }
            }
            .overlay(alignment: .topLeading) {
                BackButton(lightStyle: true) {
                    dismiss()
                }
            }
        }
        .ignoresSafeArea(.all)
        .navigationBarHidden(true)
    }
}

// Route info bubble component
struct RouteInfoBubble: View {
    let time: String
    let location: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(time)
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundColor(.white)
            
            Text(location)
                .font(.caption2)
                .foregroundColor(.white.opacity(0.8))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.black.opacity(0.4))
        )
    }
}

// MARK: - Cover Content Section Component
struct CoverContentSection: View {
    let geometry: GeometryProxy
    
    var body: some View {
        ZStack {
            // Gradient group (full height background layer)
            ZStack {
                // Gradient element 1: Base radial gradient
                RadialGradient(
                    gradient: Gradient(colors: [
                        Color.black.opacity(0.1),
                        Color.black.opacity(0.3),
                        Color.black.opacity(0.7),
                        Color.black.opacity(1)
                    ]),
                    center: .top,
                    startRadius: 50,
                    endRadius: geometry.size.height * 0.8
                )
                
                // Gradient element 2: Additional overlay gradient
                LinearGradient(
                    gradient: Gradient(colors: [
                        Color.clear,
                        Color.black.opacity(0.2),
                        Color.black.opacity(0.6)
                    ]),
                    startPoint: .top,
                    endPoint: .bottom
                )
            }
            .frame(height: geometry.size.height)
            
            // CoverContent group (content aligned to bottom)
            VStack {
                Spacer()
                
                VStack(alignment: .leading, spacing: 20) {
                    // Title
                    Text("Istanbul before Islam")
                        .font(.largeTitle)
                        .fontWeight(.bold)
                        .foregroundColor(.white)
                        .multilineTextAlignment(.leading)
                    
                    // Description
                    Text("Scelerisque ultricies pharetra imperdiet fames ultrices risus vel lorem elementum, tempor taciti mi volutpat lacinia penatibus eleifend fusce.")
                        .font(.body)
                        .foregroundColor(.white)
                        .multilineTextAlignment(.leading)
                        .lineLimit(nil)
                    
                    // Action button
                    Button(action: {
                        // TODO: Implement getting to start functionality
                        print("Getting to the Start tapped")
                    }) {
                        HStack {
                            Text("Getting to the Start")
                                .font(.headline)
                                .fontWeight(.semibold)
                            Spacer()
                            Image(systemName: "chevron.down")
                                .font(.caption)
                        }
                        .foregroundColor(.white)
                        .padding(.vertical, 16)
                        .padding(.horizontal, 20)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(Color.purple, lineWidth: 2)
                                .background(Color.black.opacity(0.3))
                        )
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 40)
            }
        }
        .frame(height: geometry.size.height)
    }
}

// MARK: - Historical Background Section Component
struct HistoricalBackgroundSection: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Historical Background")
                .font(.title2)
                .fontWeight(.bold)
                .foregroundColor(.white)
            
            Text("Istanbul, historically known as Byzantium and later Constantinople, has been a crossroads of civilizations for over two millennia. Before the arrival of Islam in the 7th century, this magnificent city was the heart of the Byzantine Empire, a Christian stronghold that bridged Europe and Asia.")
                .font(.body)
                .foregroundColor(.white)
                .multilineTextAlignment(.leading)
                .lineLimit(nil)
            
            Text("The city's strategic location on the Bosphorus Strait made it a natural meeting point for trade routes from the East and West. Greek colonists established Byzantium around 660 BCE, and it flourished under Roman rule when Emperor Constantine the Great chose it as the new capital of the Roman Empire in 330 CE.")
                .font(.body)
                .foregroundColor(.white)
                .multilineTextAlignment(.leading)
                .lineLimit(nil)
            
            Text("During the Byzantine period, Constantinople became the center of Orthodox Christianity and one of the most magnificent cities in the world. The Hagia Sophia, built by Emperor Justinian in the 6th century, stood as a testament to Byzantine architectural and engineering prowess.")
                .font(.body)
                .foregroundColor(.white)
                .multilineTextAlignment(.leading)
                .lineLimit(nil)
            
            Text("The city's walls, built by Emperor Theodosius II in the 5th century, protected Constantinople for nearly a thousand years. These massive fortifications withstood numerous sieges and attacks, making the city nearly impregnable until the advent of gunpowder and cannons.")
                .font(.body)
                .foregroundColor(.white)
                .multilineTextAlignment(.leading)
                .lineLimit(nil)
            
            Text("Byzantine Constantinople was a melting pot of cultures, languages, and religions. Greek was the dominant language, but Latin, Armenian, Syriac, and other languages were spoken in its streets. The city's markets bustled with merchants from across the known world, trading silk from China, spices from India, and precious metals from Africa.")
                .font(.body)
                .foregroundColor(.white)
                .multilineTextAlignment(.leading)
                .lineLimit(nil)
            
            Text("The Byzantine Empire's influence extended far beyond its borders. Its art, architecture, and religious traditions shaped the development of Eastern Europe, the Balkans, and Russia. The Cyrillic alphabet, still used today in many Slavic countries, was developed by Byzantine missionaries.")
                .font(.body)
                .foregroundColor(.white)
                .multilineTextAlignment(.leading)
                .lineLimit(nil)
            
            Text("As you explore the remnants of this ancient world, you'll discover how the city's pre-Islamic heritage continues to influence modern Istanbul. From the underground cisterns that once supplied water to the city, to the ancient Hippodrome where chariot races once thrilled thousands, the Byzantine legacy is woven into the very fabric of contemporary Istanbul.")
                .font(.body)
                .foregroundColor(.white)
                .multilineTextAlignment(.leading)
                .lineLimit(nil)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 30)
        .background(Color.black.opacity(1))
        .padding(.bottom, 40)
    }
}

#Preview {
    JourneyStart()
}