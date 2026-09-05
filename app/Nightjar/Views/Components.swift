import SwiftUI

/// Small uppercase monospace label. The only "header" style in the app.
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
                .font(Typeface.meta(10, weight: .semibold))
                .tracking(1.8)
                .foregroundStyle(Palette.inkFaint)
            Spacer(minLength: 8)
            if let trailing {
                Text(trailing.uppercased())
                    .font(Typeface.meta(10))
                    .tracking(1.4)
                    .foregroundStyle(Palette.inkFaint.opacity(0.75))
            }
        }
    }
}

/// Big serif title at the top of a screen, with room for one control.
struct ScreenTitle<Trailing: View>: View {
    let title: String
    var subtitle: String?
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(Typeface.display(34))
                    .foregroundStyle(Palette.ink)
                if let subtitle {
                    Text(subtitle)
                        .font(Typeface.body(14))
                        .foregroundStyle(Palette.inkSoft)
                }
            }
            Spacer(minLength: 12)
            trailing
        }
    }
}

struct Hairline: View {
    var inset: CGFloat = 0
    var body: some View {
        Rectangle()
            .fill(Palette.hairline)
            .frame(height: 1)
            .padding(.leading, inset)
    }
}

/// Horizontal level fader. Built by hand rather than using Slider so it can be
/// thin, warm and draggable anywhere along its length.
struct FaderBar: View {
    let value: Double
    var tint: Color = Palette.ember
    var height: CGFloat = 5
    let onChange: (Double) -> Void
    var onCommit: (() -> Void)?

    var body: some View {
        GeometryReader { geo in
            let width = max(geo.size.width, 1)
            ZStack(alignment: .leading) {
                Capsule(style: .continuous)
                    .fill(Palette.raisedHigh)
                    .frame(height: height)
                Capsule(style: .continuous)
                    .fill(tint.opacity(0.9))
                    .frame(width: max(width * CGFloat(value.clampedUnit), height), height: height)
            }
            .frame(maxHeight: .infinity, alignment: .center)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { gesture in
                        onChange(Double(gesture.location.x / width).clampedUnit)
                    }
                    .onEnded { _ in onCommit?() }
            )
        }
        .frame(height: 30)
    }
}

/// The one filled button in the app.
struct SoftButton: View {
    let title: String
    var systemImage: String?
    var isProminent: Bool = false
    var isWide: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 7) {
                if let systemImage {
                    Image(systemName: systemImage)
                        .font(.system(size: 12, weight: .semibold))
                }
                Text(title)
                    .font(Typeface.body(15, weight: .medium))
            }
            .foregroundStyle(isProminent ? Palette.ground : Palette.ink)
            .padding(.horizontal, 18)
            .padding(.vertical, 12)
            .frame(maxWidth: isWide ? .infinity : nil)
            .background(
                Capsule(style: .continuous)
                    .fill(isProminent ? Palette.ember : Palette.raisedHigh)
            )
        }
        .buttonStyle(.plain)
    }
}

/// A small pill: a timer, a count, a state.
struct Chip: View {
    let text: String
    var systemImage: String?
    var isLit: Bool = false

    var body: some View {
        HStack(spacing: 5) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(.system(size: 10, weight: .semibold))
            }
            Text(text)
                .font(Typeface.meta(11, weight: .medium))
        }
        .foregroundStyle(isLit ? Palette.ground : Palette.inkSoft)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            Capsule(style: .continuous)
                .fill(isLit ? Palette.ember : Palette.raised)
        )
        .overlay(
            Capsule(style: .continuous)
                .stroke(isLit ? Color.clear : Palette.hairline, lineWidth: 1)
        )
    }
}

/// Marks something that belongs to Plus. Quiet, never a padlock in a badge.
struct PlusMark: View {
    var body: some View {
        Text("PLUS")
            .font(Typeface.meta(9, weight: .semibold))
            .tracking(1.2)
            .foregroundStyle(Palette.ember)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .overlay(
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .stroke(Palette.ember.opacity(0.55), lineWidth: 1)
            )
    }
}

/// Settings-style row with a title, optional detail and trailing content.
struct SettingRow<Trailing: View>: View {
    let title: String
    var detail: String?
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(Typeface.body(15))
                    .foregroundStyle(Palette.ink)
                if let detail {
                    Text(detail)
                        .font(Typeface.body(12))
                        .foregroundStyle(Palette.inkFaint)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 8)
            trailing
        }
        .padding(.vertical, 12)
    }
}

/// Editorial list row: title, one line under it, something on the right.
struct IndexRow<Trailing: View>: View {
    let title: String
    var detail: String?
    var isActive: Bool = false
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(Typeface.body(16, weight: isActive ? .medium : .regular))
                    .foregroundStyle(isActive ? Palette.ember : Palette.ink)
                if let detail {
                    Text(detail)
                        .font(Typeface.body(12))
                        .foregroundStyle(Palette.inkFaint)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 8)
            trailing
        }
        .padding(.vertical, 13)
        .contentShape(Rectangle())
    }
}

struct WarmToggleStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        Button {
            withAnimation(.settle) { configuration.isOn.toggle() }
        } label: {
            ZStack(alignment: configuration.isOn ? .trailing : .leading) {
                Capsule()
                    .fill(configuration.isOn ? Palette.ember.opacity(0.9) : Palette.raisedHigh)
                    .frame(width: 44, height: 26)
                Circle()
                    .fill(configuration.isOn ? Palette.ground : Palette.inkSoft)
                    .frame(width: 20, height: 20)
                    .padding(.horizontal, 3)
            }
        }
        .buttonStyle(.plain)
    }
}

/// Horizontal row of choices. Replaces Picker, which cannot be made to look
/// like anything but a Picker.
struct ChoiceRow<Value: Hashable>: View {
    let options: [(value: Value, label: String)]
    let selection: Value
    let onSelect: (Value) -> Void

    var body: some View {
        HStack(spacing: 6) {
            ForEach(options, id: \.value) { option in
                let isSelected = option.value == selection
                Button {
                    onSelect(option.value)
                } label: {
                    Text(option.label)
                        .font(Typeface.meta(12, weight: isSelected ? .semibold : .regular))
                        .foregroundStyle(isSelected ? Palette.ground : Palette.inkSoft)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 9)
                        .background(
                            RoundedRectangle(cornerRadius: 9, style: .continuous)
                                .fill(isSelected ? Palette.ember : Palette.raised)
                        )
                }
                .buttonStyle(.plain)
            }
        }
    }
}

/// Empty-state copy. Short, never chirpy.
struct QuietNotice: View {
    let text: String
    var body: some View {
        Text(text)
            .font(Typeface.body(14))
            .foregroundStyle(Palette.inkFaint)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 40)
    }
}

/// Round icon button for headers and sheets.
struct IconButton: View {
    let systemImage: String
    var size: CGFloat = 34
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: size * 0.4, weight: .semibold))
                .foregroundStyle(Palette.inkSoft)
                .frame(width: size, height: size)
                .background(Circle().fill(Palette.raised))
                .overlay(Circle().stroke(Palette.hairline, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
}

/// A sheet's title line with a close control.
struct SheetHeader: View {
    let title: String
    var subtitle: String?
    let onClose: () -> Void

    var body: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(Typeface.display(28))
                    .foregroundStyle(Palette.ink)
                if let subtitle {
                    Text(subtitle)
                        .font(Typeface.body(13))
                        .foregroundStyle(Palette.inkSoft)
                }
            }
            Spacer(minLength: 12)
            IconButton(systemImage: "xmark", size: 32, action: onClose)
        }
        .padding(.top, 20)
    }
}

/// Presents the upgrade sheet from whichever screen is on top. A sheet cannot
/// present another sheet from underneath it, so every presented screen that
/// can call `requestUpgrade` carries this as well as the root.
private struct PaywallHost: ViewModifier {
    @Environment(PlayerController.self) private var player

    func body(content: Content) -> some View {
        @Bindable var player = player
        return content.sheet(item: $player.paywall) { reason in
            PaywallView(reason: reason)
        }
    }
}

extension View {
    func paywallHost() -> some View { modifier(PaywallHost()) }
}

extension Double {
    var clampedUnit: Double { self < 0 ? 0 : (self > 1 ? 1 : self) }
}

extension View {
    /// Page gutter. One number, used everywhere.
    func pageGutter() -> some View { padding(.horizontal, 22) }

    /// Standard sheet dressing: ground colour, warm drag indicator.
    func sheetDressing() -> some View {
        self
            .presentationBackground(Palette.ground)
            .presentationDragIndicator(.visible)
            .preferredColorScheme(.dark)
    }
}
