import SwiftUI
import MapKit

struct AddrSearchResultItem: View {
    let result: MKLocalSearchCompletion
    let isMostRelevant: Bool
    let onSelect: (MKLocalSearchCompletion) -> Void
    
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
                    Text(result.title)
                        .heading(size: .article0)
                        .foregroundColor(isMostRelevant ? Color("onBkgTextColor10") : Color("onBkgTextColor20").opacity(0.5))
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    
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

