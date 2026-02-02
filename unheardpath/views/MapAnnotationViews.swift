import SwiftUI
import SafariServices
import CoreLocation
import core

// MARK: - Custom Annotation View
/// Custom SwiftUI view for GeoJSON feature annotations
/// Used with MapViewAnnotation to display feature information on the map
struct PlaceView: View {
    let feature: PointFeature
    @State private var showWebPage: Bool = false
    
    /// Frame size for the circular image
    private let imageFrameSize: CGFloat = Spacing.current.spaceL
    
    /// Handles tap action on the place annotation
    private func handleTap() {
        if feature.wikipediaURL != nil {
            showWebPage = true
        }
    }
    
    var body: some View {
        VStack(spacing: 4) {
            // Image in circular clip (only show if img_url exists)
            if let imageURL = feature.imageURL {
                AsyncImage(url: imageURL) { phase in
                    switch phase {
                    case .empty:
                        ProgressView()
                            .frame(width: imageFrameSize, height: imageFrameSize)
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFill()
                            .frame(width: imageFrameSize, height: imageFrameSize)
                            .clipShape(Circle())
                            .overlay(Circle().stroke(Color("AppBkgColor"), lineWidth: 2))
                            .shadow(radius: Spacing.current.space3xs)
                    case .failure:
                        #if DEBUG
                        let _ = print("⚠️ Failed to load image from URL: \(imageURL.absoluteString)")
                        #endif
                        EmptyView()
                    @unknown default:
                        EmptyView()
                    }
                }
            }
            
            // Title text (only show if title exists)
            if let title = feature.title {
                Text(title)
                    .bodyText(size: .articleMinus1)
                    .foregroundColor(Color("onBkgTextColor10"))
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .padding(.vertical,Spacing.current.space3xs)
                    .padding(.horizontal,Spacing.current.space2xs)
                    .background(Color("AppBkgColor").cornerRadius(Spacing.current.spaceXs))
                    .shadow(radius: Spacing.current.space3xs)
            }
            // Pin icon
            Image(systemName: "arrowtriangle.down.fill")
                .font(.system(size: Spacing.current.spaceXs))
                .foregroundColor(Color("AppBkgColor"))
                .shadow(radius: Spacing.current.space3xs)
            
        }
        .contentShape(Rectangle())
        .onTapGesture {
            handleTap()
        }
        .sheet(isPresented: $showWebPage) {
            if let url = feature.wikipediaURL {
                SafariView(url: url)
            }
        }
    }
}

// MARK: - Lookup Location Annotation View
/// Custom SwiftUI view for lookup location annotations (from autocomplete selection or long press)
/// Used with MapViewAnnotation to display lookup place information on the map
struct LookupLocation: View {
    let flyToLocation: FlyToLocation

    var body: some View {
        VStack(spacing: 4) {
            // Pin icon
            Image(systemName: "mappin.circle.fill")
                .font(.system(size: Spacing.current.spaceM))
                .foregroundColor(Color("AppBkgColor"))
                .shadow(radius: Spacing.current.space3xs)

            // Place name text (only show if name exists)
            if let name = flyToLocation.name {
                Text(name)
                    .bodyText(size: .articleMinus1)
                    .foregroundColor(Color("onBkgTextColor10"))
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .padding(.vertical, Spacing.current.space3xs)
                    .padding(.horizontal, Spacing.current.space2xs)
                    .background(Color("AppBkgColor").cornerRadius(Spacing.current.spaceXs))
                    .shadow(radius: Spacing.current.space3xs)
            }
        }
    }
}

