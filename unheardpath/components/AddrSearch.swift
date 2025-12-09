import SwiftUI
@preconcurrency import MapKit

struct AddrSearchResultItem: View {
    let result: AddressSearchResult
    let isMostRelevant: Bool
    let onSelect: (AddressSearchResult) -> Void
    
    var body: some View {
        Button(action: {
            onSelect(result)
        }) {
            HStack(alignment: .top, spacing: Spacing.current.spaceXs) {
                Image(systemName: "mappin.circle.fill")
                    .bodyText(size: .article1)
                    .foregroundColor(isMostRelevant ? Color("onBkgTextColor10") : Color("onBkgTextColor20").opacity(0.5))
                    .padding(.top, 2) // Align icon with first line of text
                
                VStack(alignment: .leading, spacing: Spacing.current.space3xs) {
                    HStack(alignment: .top) {
                        Text(result.title)
                            .heading(size: .article0)
                            .foregroundColor(isMostRelevant ? Color("onBkgTextColor10") : Color("onBkgTextColor20").opacity(0.5))
                            .multilineTextAlignment(.leading)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        
                        #if DEBUG
                        // Debug-only source indicator
                        Text(sourceIndicator)
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(sourceColor)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 2)
                            .background(sourceColor.opacity(0.2))
                            .cornerRadius(4)
                        #endif
                    }
                    
                    if !result.subtitle.isEmpty {
                        Text(result.subtitle)
                            .bodyText(size: .articleMinus1)
                            .foregroundColor(isMostRelevant ? Color("onBkgTextColor20") : Color("onBkgTextColor20").opacity(0.5))
                            .multilineTextAlignment(.leading)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                
                Spacer()
            }
            .padding(.horizontal, Spacing.current.spaceXs)
            .padding(.vertical, Spacing.current.space2xs)
            .cornerRadius(Spacing.current.spaceS)
        }
    }
    
    #if DEBUG
    /// Debug-only source indicator text
    private var sourceIndicator: String {
        switch result.source {
        case .geoapify:
            return "GA"
        case .mapkit:
            return "MK"
        }
    }
    
    /// Debug-only source indicator color
    private var sourceColor: Color {
        switch result.source {
        case .geoapify:
            return .blue
        case .mapkit:
            return .orange
        }
    }
    #endif
}

// MARK: - Address Search Results List
struct AddrSearchResultsList: View {
    let searchResults: [AddressSearchResult]
    @Binding var inputLocation: String
    @FocusState.Binding var isTextFieldFocused: Bool
    let onResultSelected: (AddressSearchResult) async -> Void
    let onClearResults: () -> Void
    
    var body: some View {
        let lastIndex = searchResults.count - 1
        
        VStack {
            Spacer()
            VStack(alignment: .leading, spacing: Spacing.current.space2xs) {
                ForEach(Array(searchResults.enumerated()), id: \.offset) { index, result in
                    let isMostRelevant = index == lastIndex
                    
                    AddrSearchResultItem(
                        result: result,
                        isMostRelevant: isMostRelevant,
                        onSelect: { selectedResult in
                            // Handle selection - geocode and update map
                            inputLocation = selectedResult.title
                            onClearResults()
                            isTextFieldFocused = false
                            
                            // Geocode the selected location and fly to it
                            Task {
                                await onResultSelected(selectedResult)
                            }
                        }
                    )
                }
            }
            .padding(.top, Spacing.current.spaceXs)
            .padding(.horizontal, Spacing.current.spaceXs)
            .background(Color("AppBkgColor"))
        }
    }
}

#if DEBUG
// MARK: - Preview Helper Component
/// Preview-only component that displays the same UI as AddrSearchResultItem
/// but takes data directly instead of requiring MKLocalSearchCompletion
private struct AddrSearchResultItemPreview: View {
    let title: String
    let subtitle: String
    let isMostRelevant: Bool
    
    var body: some View {
        Button(action: {}) {
            HStack(alignment: .top, spacing: Spacing.current.spaceXs) {
                Image(systemName: "mappin.circle.fill")
                    .bodyText(size: .article1)
                    .foregroundColor(isMostRelevant ? Color("onBkgTextColor10") : Color("onBkgTextColor20").opacity(0.5))
                    .padding(.top, 2) // Align icon with first line of text
                
                VStack(alignment: .leading, spacing: Spacing.current.space3xs) {
                    Text(title)
                        .heading(size: .article0)
                        .foregroundColor(isMostRelevant ? Color("onBkgTextColor10") : Color("onBkgTextColor20").opacity(0.5))
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    
                    if !subtitle.isEmpty {
                        Text(subtitle)
                            .bodyText(size: .articleMinus1)
                            .foregroundColor(isMostRelevant ? Color("onBkgTextColor20") : Color("onBkgTextColor20").opacity(0.5))
                            .multilineTextAlignment(.leading)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                
                Spacer()
            }
            .padding(.horizontal, Spacing.current.spaceXs)
            .padding(.vertical, Spacing.current.space2xs)
            .cornerRadius(Spacing.current.spaceS)
        }
    }
}

#Preview("Autocomplete Result Items - Comparison") {
    VStack(alignment: .leading, spacing: Spacing.current.spaceXl) {
        VStack(alignment: .leading, spacing: Spacing.current.space2xs) {
            Text("Most Relevant")
            AddrSearchResultItemPreview(
                title: "Central Park",
                subtitle: "New York, NY, United States",
                isMostRelevant: true
            )
            .background(Color("AppBkgColor"))
        }
        VStack(alignment: .leading, spacing: Spacing.current.space2xs) {
            Text("Less Relevant")
            AddrSearchResultItemPreview(
                title: "Central Park Zoo",
                subtitle: "830 5th Ave, New York, NY 10065, United States",
                isMostRelevant: false
            )
            .background(Color("AppBkgColor"))
            }
    }
}

#endif

