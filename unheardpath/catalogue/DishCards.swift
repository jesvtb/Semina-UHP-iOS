import SwiftUI
import core

// MARK: - Dish Card Defaults
/// Dish-specific layout defaults, used when server config doesn't specify values.
private enum DishCardDefaults {
    static let aspectRatio: CGFloat = 1.4
}

/// A dish card item
struct Dish: Identifiable {
    let localName: String
    let globalName: String
    let description: String
    let imageURL: URL?

    var id: String { "\(localName)|\(globalName)" }
}

// MARK: - Dish Card Content (render_type: "dish")
/// Renders dish cards using `DynamicCardGrid` with `DishCard` as the internal card view.
/// Manages dish popup state and parses JSONValue into Dish models.
struct DishCardContent: View {
    let cards: [JSONValue]
    let config: JSONValue?
    @State private var selectedDish: Dish?
    @Environment(\.isPopupEnabled) private var isPopupEnabled
    
    /// Effective config: dish defaults overlaid with any server-provided overrides.
    private var effectiveConfig: JSONValue {
        var dict: [String: JSONValue] = [
            "aspectRatio": .double(DishCardDefaults.aspectRatio),
            "cornerRadius": .double(CardConstants.cornerRadius)
        ]
        // Server config overrides dish defaults
        if case .dictionary(let serverDict) = config {
            for (key, value) in serverDict {
                dict[key] = value
            }
        }
        return .dictionary(dict)
    }
    
    var body: some View {
        DynamicCardGrid(cards: cards, config: effectiveConfig) { cardData in
            dishCardView(from: cardData)
        }
        .sheet(item: $selectedDish) { dish in
            DishPopupView(dish: dish) {
                selectedDish = nil
            }
        }
    }
    
    @ViewBuilder
    private func dishCardView(from data: JSONValue) -> some View {
        if let dish = parseDish(from: data) {
            DishCard(dish: dish, config: config) {
                if isPopupEnabled {
                    selectedDish = dish
                }
            }
        }
    }
    
    private func parseDish(from data: JSONValue) -> Dish? {
        guard case .dictionary(let dict) = data else { return nil }
        guard let localName = dict["local_name"]?.stringValue,
              let globalName = dict["global_name"]?.stringValue,
              let description = dict["description"]?.stringValue else {
            return nil
        }
        let imageURL = dict["img_url"]?.stringValue.flatMap { URL(string: $0) }
        return Dish(localName: localName, globalName: globalName, description: description, imageURL: imageURL)
    }
}

struct DishCard: View {
    let dish: Dish
    let config: JSONValue?
    let onTap: () -> Void
    
    /// Corner radius from config, falling back to dish-specific default
    private var cornerRadius: CGFloat {
        config?["cornerRadius"]?.doubleValue.map { CGFloat($0) } ?? CardConstants.cornerRadius
    }

    var body: some View {
        Button(action: onTap) {
            GeometryReader { geometry in
                ZStack(alignment: .bottomLeading) {
                    cardBackground
                    gradientOverlay
                    textOverlay(cardWidth: geometry.size.width)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .stroke(Color("onBkgTextColor30").opacity(0.15), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
    }

    @ViewBuilder
    private var cardBackground: some View {
        Group {
            if let imageURL = dish.imageURL {
                AsyncImage(url: imageURL) { phase in
                    switch phase {
                    case .empty:
                        Rectangle()
                            .fill(Color("onBkgTextColor30").opacity(0.15))
                            .overlay(ProgressView().tint(Color("onBkgTextColor30")))
                    case .success(let image):
                        GeometryReader { geo in
                            image
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                                .frame(width: geo.size.width, height: geo.size.height)
                                .clipped()
                        }
                    case .failure:
                        Rectangle()
                            .fill(Color("onBkgTextColor30").opacity(0.15))
                            .overlay(
                                Image(systemName: "photo")
                                    .font(.system(size: 36))
                                    .foregroundColor(Color("onBkgTextColor30").opacity(0.4))
                            )
                    @unknown default:
                        Rectangle()
                            .fill(Color("onBkgTextColor30").opacity(0.15))
                    }
                }
            } else {
                Rectangle()
                    .fill(Color("onBkgTextColor30").opacity(0.15))
                    .overlay(
                        Image(systemName: "photo")
                            .font(.system(size: 36))
                            .foregroundColor(Color("onBkgTextColor30").opacity(0.4))
                    )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var gradientOverlay: some View {
        LinearGradient(
            colors: [
                Color.clear,
                Color.black.opacity(0.1),
                Color.black.opacity(0.7)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    private func textOverlay(cardWidth: CGFloat) -> some View {
        let horizontalPadding = Spacing.current.spaceXs * 2
        let maxTextWidth = max(0, cardWidth - horizontalPadding)
        return VStack(alignment: .leading, spacing: 2) {
            DisplayText(
                dish.globalName,
                scale: .article1,
                color: .white,
                lineHeightMultiple: 1.0,
                fontFamily: FontFamily.sansSemibold
            )
            if dish.localName != dish.globalName {
                DisplayText(
                    dish.localName,
                    scale: .articleMinus1,
                    color: .white.opacity(0.9),
                    lineHeightMultiple: 1.0,
                    fontFamily: FontFamily.sansRegular
                )
            }
        }
        .frame(width: maxTextWidth, alignment: .leading)
        .padding(.horizontal, Spacing.current.spaceXs)
        .padding(.vertical, Spacing.current.spaceXs)
        .clipped()
    }
}

/// Popup presented when a regional dish card is tapped.
struct DishPopupView: View {
    let dish: Dish
    let onDismiss: () -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.current.spaceS) {
                    if let imageURL = dish.imageURL {
                        AsyncImage(url: imageURL) { phase in
                            switch phase {
                            case .empty:
                                Rectangle()
                                    .fill(Color("onBkgTextColor30").opacity(0.1))
                                    .frame(height: 220)
                                    .overlay(ProgressView().tint(Color("onBkgTextColor30")))
                            case .success(let image):
                                image
                                    .resizable()
                                    .aspectRatio(contentMode: .fill)
                                    .frame(maxHeight: 220)
                                    .clipped()
                            case .failure:
                                Rectangle()
                                    .fill(Color("onBkgTextColor30").opacity(0.1))
                                    .frame(height: 220)
                                    .overlay(
                                        Image(systemName: "photo")
                                            .foregroundColor(Color("onBkgTextColor30").opacity(0.5))
                                    )
                            @unknown default:
                                EmptyView()
                            }
                        }
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    }

                    Text(dish.localName)
                        .bodyText(size: .article2)
                        .foregroundColor(Color("onBkgTextColor20"))
                    if dish.globalName != dish.localName {
                        Text(dish.globalName)
                            .bodyText(size: .articleMinus1)
                            .foregroundColor(Color("onBkgTextColor30"))
                    }
                    Text(dish.description)
                        .bodyParagraph(color: Color("onBkgTextColor30"))
                }
                .padding(Spacing.current.spaceS)
            }
            .navigationTitle(dish.localName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        onDismiss()
                    }
                }
            }
        }
    }
}

#Preview("Dish Card") {
    DishCard(dish: Dish(localName: "Dish", globalName: "Dish", description: "Description", imageURL: URL(string: "https://i2.wp.com/www.downshiftology.com/wp-content/uploads/2023/12/Shakshuka-main-1.jpg")), config: nil) {
        print("Tapped")
    }
}

#Preview("Dish Card Content") {
    ScrollView {
        DishCardContent(cards: [
            JSONValue.dictionary([
                "local_name": .string("Shakshuka"),
                "global_name": .string("Shakshuka"),
                "description": .string("A Middle Eastern and North African dish of eggs poached in a sauce of tomatoes, olive oil, peppers, onion, and garlic, commonly spiced with cumin, paprika, and cayenne pepper."),
                "img_url": .string("https://i2.wp.com/www.downshiftology.com/wp-content/uploads/2023/12/Shakshuka-main-1.jpg")
            ]),
            JSONValue.dictionary([
                "local_name": .string("Paella"),
                "global_name": .string("Paella Valenciana"),
                "description": .string("A traditional Spanish rice dish originally from Valencia, made with saffron, green beans, white beans, rabbit, chicken, and snails."),
                "img_url": .string("https://upload.wikimedia.org/wikipedia/commons/e/ed/Paella_mixta.jpg")
            ]),
            JSONValue.dictionary([
                "local_name": .string("Phở"),
                "global_name": .string("Pho"),
                "description": .string("A Vietnamese soup consisting of broth, rice noodles, herbs, and meat — usually beef or chicken. A staple of Vietnamese cuisine."),
                "img_url": .string("https://upload.wikimedia.org/wikipedia/commons/5/53/Pho-Beef-Noodles-2008.jpg")
            ]),
            JSONValue.dictionary([
                "local_name": .string("たこ焼き"),
                "global_name": .string("Takoyaki"),
                "description": .string("A ball-shaped Japanese snack made of wheat flour batter and filled with minced octopus, tempura scraps, pickled ginger, and green onion."),
                "img_url": .string("https://upload.wikimedia.org/wikipedia/commons/a/a7/Takoyaki_by_rhosoi_in_Osaka.jpg")
            ]),
            JSONValue.dictionary([
                "local_name": .string("Ceviche"),
                "global_name": .string("Ceviche"),
                "description": .string("A South American seafood dish that originated in Peru, typically made from fresh raw fish cured in citrus juices and spiced with chili peppers."),
                "img_url": .string("https://upload.wikimedia.org/wikipedia/commons/thumb/f/fa/Ceviche_de_corvina.jpg/1280px-Ceviche_de_corvina.jpg")
            ])
        ], config: nil)
        .padding()
    }
}
