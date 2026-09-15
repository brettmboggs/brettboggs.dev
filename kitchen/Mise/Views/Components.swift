import SwiftUI

/// Small uppercase monospace label. The only heading style in the app.
struct SectionLabel: View {
    let text: String
    var trailing: String?

    init(_ text: String, trailing: String? = nil) {
        self.text = text
        self.trailing = trailing
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(text.uppercased())
                .font(Typeface.meta(11, weight: .semibold))
                .tracking(1.6)
                .foregroundStyle(Ink.inkSoft)
            Spacer(minLength: 8)
            if let trailing {
                Text(trailing)
                    .font(Typeface.meta(11))
                    .foregroundStyle(Ink.inkFaint)
            }
        }
        .padding(.top, 6)
        .accessibilityAddTraits(.isHeader)
    }
}

struct Hairline: View {
    var body: some View {
        Rectangle()
            .fill(Ink.hairline)
            .frame(height: 1)
    }
}

/// A 2px rule, the one heavier line, used under screen titles.
struct Rule: View {
    var body: some View {
        Rectangle()
            .fill(Ink.ink)
            .frame(height: 2)
    }
}

/// The filled black (or white) button. One per screen at most.
struct InkButton: View {
    let title: String
    var systemImage: String?
    var isProminent: Bool = true
    var isWide: Bool = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if let systemImage {
                    Image(systemName: systemImage)
                        .font(.system(size: 14, weight: .semibold))
                }
                Text(title)
                    .font(Typeface.body(16, weight: .semibold))
            }
            .foregroundStyle(isProminent ? Ink.paper : Ink.ink)
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
            .frame(maxWidth: isWide ? .infinity : nil)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(isProminent ? Ink.ink : Ink.paper)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Ink.ink, lineWidth: isProminent ? 0 : 1.5)
            )
        }
        .buttonStyle(.plain)
    }
}

/// A small round action: favourite, share, plan.
struct IconButton: View {
    let systemImage: String
    let label: String
    var filled: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: systemImage)
                    .font(.system(size: 17, weight: .medium))
                    .frame(width: 46, height: 46)
                    .background(Circle().fill(filled ? Ink.ink : Ink.paperRaised))
                    .foregroundStyle(filled ? Ink.paper : Ink.ink)
                Text(label)
                    .font(Typeface.meta(10))
                    .foregroundStyle(Ink.inkSoft)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}

/// A selectable pill: filters, tags, unit systems.
struct Chip: View {
    let title: String
    var isSelected: Bool = false
    var count: Int?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Text(title)
                    .font(Typeface.body(14, weight: .medium))
                if let count, count > 0 {
                    Text("\(count)")
                        .font(Typeface.meta(11))
                        .opacity(0.7)
                }
            }
            .padding(.horizontal, 13)
            .padding(.vertical, 8)
            .foregroundStyle(isSelected ? Ink.paper : Ink.ink)
            .background(Capsule().fill(isSelected ? Ink.ink : Ink.paper))
            .overlay(Capsule().stroke(isSelected ? Ink.ink : Ink.hairline, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
}

/// The circle that gets ticked: ingredients, shopping, steps.
struct CheckCircle: View {
    let isOn: Bool
    var size: CGFloat = 22

    var body: some View {
        ZStack {
            Circle()
                .stroke(isOn ? Ink.ink : Ink.hairline, lineWidth: 1.5)
            if isOn {
                Circle()
                    .fill(Ink.ink)
                    .padding(4)
            }
        }
        .frame(width: size, height: size)
        .contentShape(Circle())
        .animation(.settle, value: isOn)
    }
}

/// The small dot that says whether the kitchen has an ingredient.
enum Presence {
    case have
    case partial
    case missing

    init(_ status: IngredientMatch.Status) {
        switch status {
        case .have, .staple: self = .have
        case .substitute: self = .partial
        case .missing: self = .missing
        }
    }
}

struct PresenceDot: View {
    let presence: Presence

    init(_ presence: Presence) {
        self.presence = presence
    }

    init(status: IngredientMatch.Status) {
        self.presence = Presence(status)
    }

    var body: some View {
        Group {
            switch presence {
            case .have:
                Circle().fill(Ink.ink)
            case .partial:
                Circle().stroke(Ink.ink, lineWidth: 1.5)
                    .overlay(Circle().fill(Ink.ink).padding(3))
            case .missing:
                Circle().stroke(Ink.hairline, lineWidth: 1.5)
            }
        }
        .frame(width: 9, height: 9)
    }
}

struct StarRating: View {
    @Binding var rating: Int
    var size: CGFloat = 28

    var body: some View {
        HStack(spacing: 6) {
            ForEach(1...5, id: \.self) { star in
                Image(systemName: star <= rating ? "star.fill" : "star")
                    .font(.system(size: size, weight: .light))
                    .foregroundStyle(star <= rating ? Ink.ink : Ink.inkFaint)
                    .onTapGesture {
                        rating = (rating == star) ? 0 : star
                        Haptics.tap()
                    }
                    .accessibilityLabel("\(star) star")
            }
        }
    }
}

struct StaticStars: View {
    let rating: Double

    var body: some View {
        HStack(spacing: 2) {
            ForEach(1...5, id: \.self) { star in
                Image(systemName: Double(star) <= rating.rounded() ? "star.fill" : "star")
                    .font(.system(size: 10))
            }
        }
        .foregroundStyle(Ink.inkSoft)
    }
}

/// A recipe's photo, or its initial in serif on grey when it has none.
struct RecipeThumb: View {
    let recipe: Recipe
    var side: CGFloat = 60
    var cornerRadius: CGFloat = 10

    @State private var image: UIImage?

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(Ink.paperRaised)
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Text(String(recipe.title.trimmingCharacters(in: .whitespaces).prefix(1)).uppercased())
                    .font(Typeface.display(side * 0.46))
                    .foregroundStyle(Ink.inkSoft)
            }
        }
        .frame(width: side, height: side)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .task(id: recipe.photoID) {
            image = nil
            guard let id = recipe.photoID else { return }
            image = await PhotoStore.thumbnail(id, side: side)
        }
    }
}

/// A stored photo at full size, loaded when shown.
struct StoredPhoto: View {
    let id: String
    var contentMode: ContentMode = .fill

    @State private var image: UIImage?

    var body: some View {
        ZStack {
            Ink.paperRaised
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: contentMode)
            }
        }
        .task(id: id) {
            image = await Task.detached(priority: .userInitiated) { PhotoStore.load(id) }.value
        }
    }
}

/// A row in an index: title, one line of meta, an optional thumb.
struct IndexRow<Trailing: View>: View {
    let title: String
    var subtitle: String?
    var thumb: Recipe?
    @ViewBuilder var trailing: Trailing

    init(title: String, subtitle: String? = nil, thumb: Recipe? = nil, @ViewBuilder trailing: () -> Trailing) {
        self.title = title
        self.subtitle = subtitle
        self.thumb = thumb
        self.trailing = trailing()
    }

    var body: some View {
        HStack(spacing: 14) {
            if let thumb {
                RecipeThumb(recipe: thumb, side: 56)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(Typeface.display(19))
                    .foregroundStyle(Ink.ink)
                    .lineLimit(2)
                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(Typeface.meta(11))
                        .foregroundStyle(Ink.inkSoft)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 8)
            trailing
        }
        .padding(.vertical, 6)
    }
}

extension IndexRow where Trailing == EmptyView {
    init(title: String, subtitle: String? = nil, thumb: Recipe? = nil) {
        self.init(title: title, subtitle: subtitle, thumb: thumb) { EmptyView() }
    }
}

/// The big serif title at the top of a tab.
struct ScreenTitle: View {
    let title: String
    var subtitle: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(Typeface.display(38))
                .foregroundStyle(Ink.ink)
            if let subtitle, !subtitle.isEmpty {
                Text(subtitle)
                    .font(Typeface.meta(12))
                    .foregroundStyle(Ink.inkSoft)
            }
            Rule()
                .padding(.top, 8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .listRowSeparator(.hidden)
        .listRowInsets(EdgeInsets(top: 8, leading: 20, bottom: 12, trailing: 20))
    }
}

/// A line of small monospace metadata: "45 min · Serves 4".
struct MetaText: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(text)
            .font(Typeface.meta(12))
            .foregroundStyle(Ink.inkSoft)
    }
}

/// A short message for an empty screen, with one thing to do about it.
struct EmptyNote: View {
    let title: String
    let message: String
    var actionTitle: String?
    var action: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(Typeface.display(24))
            Text(message)
                .font(Typeface.body(15))
                .foregroundStyle(Ink.inkSoft)
                .fixedSize(horizontal: false, vertical: true)
            if let actionTitle, let action {
                InkButton(title: actionTitle, isWide: false, action: action)
                    .padding(.top, 6)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 12)
        .listRowSeparator(.hidden)
    }
}

/// A quiet, plain list: no grouping chrome, hairline separators.
struct QuietListModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(Ink.paper)
    }
}

extension View {
    func plainList() -> some View {
        modifier(QuietListModifier())
    }

    /// Standard row insets for the index screens.
    func indexInsets() -> some View {
        listRowInsets(EdgeInsets(top: 6, leading: 20, bottom: 6, trailing: 20))
    }
}
