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
                    .frame(width: max(width * value.clampedUnit, height), height: height)
            }
            .frame(maxHeight: .infinity, alignment: .center)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { gesture in
                        onChange((gesture.location.x / width).clampedUnit)
                    }
                    .onEnded { _ in onCommit?() }
            )
        }
        .frame(height: 30)
    }
}

/// A dot that pulses with the running mix. Used instead of a play icon in lists.
struct PulseDot: View {
    let isActive: Bool
    let level: Double
    var tint: Color = Palette.ember

    var body: some View {
        Circle()
            .fill(isActive ? tint : Palette.hairline)
            .frame(width: 7, height: 7)
            .scaleEffect(isActive ? 1 + level * 0.55 : 1)
            .animation(.easeOut(duration: 0.18), value: level)
            .animation(.settle, value: isActive)
    }
}

/// The one filled button in the app.
struct SoftButton: View {
    let title: String
    var systemImage: String?
    var isProminent: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 7) {
                if let systemImage {
                    Image(systemName: systemImage)
                        .font(.system(size: 12, weight: .semibold))
                }
                Text(title)
                    .font(Typeface.body(14, weight: .medium))
            }
            .foregroundStyle(isProminent ? Palette.ground : Palette.ink)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(
                Capsule(style: .continuous)
                    .fill(isProminent ? Palette.ember : Palette.raisedHigh)
            )
        }
        .buttonStyle(.plain)
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

extension Double {
    var clampedUnit: Double { self < 0 ? 0 : (self > 1 ? 1 : self) }
}

extension View {
    /// Page gutter. One number, used everywhere.
    func pageGutter() -> some View { padding(.horizontal, 22) }
}
