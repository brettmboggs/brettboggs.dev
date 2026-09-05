import SwiftUI

struct SoundsView: View {
    @Environment(PlayerController.self) private var player
    @State private var shapingSound: SoundKind?

    var body: some View {
        ZStack {
            Palette.ground.ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 30) {
                    heading

                    ForEach(SoundCatalog.shelves, id: \.family) { shelf in
                        VStack(alignment: .leading, spacing: 0) {
                            SectionLabel(shelf.family.title)
                                .padding(.bottom, 10)

                            ForEach(shelf.sounds) { kind in
                                soundRow(kind)
                                if kind.id != shelf.sounds.last?.id {
                                    Hairline(inset: 18)
                                }
                            }
                        }
                    }
                }
                .pageGutter()
                .padding(.top, 8)
                .padding(.bottom, 40)
            }
        }
        .sheet(item: $shapingSound) { kind in SoundShapingSheet(kind: kind) }
    }

    private var heading: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Sounds")
                .font(Typeface.display(32))
                .foregroundStyle(Palette.ink)
            Text("Every one of these is generated as it plays. Nothing loops.")
                .font(Typeface.body(13))
                .foregroundStyle(Palette.inkFaint)
        }
        .padding(.top, 14)
    }

    private func soundRow(_ kind: SoundKind) -> some View {
        let isActive = player.isActive(kind.id)
        let layer = player.currentMix.layer(for: kind.id)
        let tint = Palette.tint(for: kind.family)

        return VStack(spacing: 0) {
            Button {
                player.toggleSound(kind)
            } label: {
                HStack(spacing: 12) {
                    PulseDot(
                        isActive: isActive && player.isPlaying,
                        level: player.meterLevel,
                        tint: tint
                    )

                    VStack(alignment: .leading, spacing: 3) {
                        Text(kind.name)
                            .font(Typeface.body(15, weight: isActive ? .semibold : .regular))
                            .foregroundStyle(isActive ? Palette.ink : Palette.ink.opacity(0.86))
                        Text(kind.blurb)
                            .font(Typeface.body(12))
                            .foregroundStyle(Palette.inkFaint)
                    }

                    Spacer(minLength: 8)

                    Image(systemName: isActive ? "checkmark" : "plus")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(isActive ? tint : Palette.inkFaint)
                        .frame(width: 26, height: 26)
                        .background(
                            Circle().fill(isActive ? tint.opacity(0.14) : Palette.raised)
                        )
                }
                .padding(.vertical, 13)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isActive, let layer {
                HStack(spacing: 12) {
                    FaderBar(
                        value: layer.level,
                        tint: tint,
                        onChange: { player.setLevel($0, for: kind.id) }
                    )
                    Button {
                        shapingSound = kind
                    } label: {
                        Image(systemName: "dial.medium")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(Palette.inkSoft)
                            .frame(width: 30, height: 30)
                            .background(Circle().fill(Palette.raised))
                    }
                    .buttonStyle(.plain)
                }
                .padding(.leading, 19)
                .padding(.bottom, 12)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .animation(.settle, value: isActive)
    }
}

// MARK: - Shaping

/// The two continuous controls that make a texture yours. This is the thing a
/// library of recorded loops cannot do.
struct SoundShapingSheet: View {
    let kind: SoundKind
    @Environment(PlayerController.self) private var player
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        SheetShell(title: kind.name) {
            let layer = player.currentMix.layer(for: kind.id)
            let tint = Palette.tint(for: kind.family)

            VStack(alignment: .leading, spacing: 26) {
                Text(kind.blurb)
                    .font(Typeface.body(14))
                    .foregroundStyle(Palette.inkSoft)

                if let layer {
                    control(
                        label: "Level",
                        value: layer.level,
                        tint: tint,
                        readout: "\(Int(layer.level * 100))"
                    ) { player.setLevel($0, for: kind.id) }

                    control(
                        label: kind.toneLabel,
                        value: layer.tone,
                        tint: tint,
                        readout: "\(Int(layer.tone * 100))"
                    ) { player.setTone($0, for: kind.id) }

                    control(
                        label: kind.motionLabel,
                        value: layer.motion,
                        tint: tint,
                        readout: "\(Int(layer.motion * 100))"
                    ) { player.setMotion($0, for: kind.id) }

                    HStack(spacing: 10) {
                        SoftButton(title: "Reset") {
                            player.setLevel(kind.defaultLevel, for: kind.id)
                            player.setTone(kind.defaultTone, for: kind.id)
                            player.setMotion(kind.defaultMotion, for: kind.id)
                        }
                        SoftButton(title: "Remove", systemImage: "minus") {
                            player.remove(soundID: kind.id)
                            dismiss()
                        }
                        Spacer()
                    }
                    .padding(.top, 4)
                } else {
                    QuietNotice(text: "Add this sound to shape it.")
                    SoftButton(title: "Add to mix", systemImage: "plus", isProminent: true) {
                        player.add(kind)
                    }
                }
            }
        }
    }

    private func control(
        label: String,
        value: Double,
        tint: Color,
        readout: String,
        onChange: @escaping (Double) -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionLabel(label, trailing: readout)
            FaderBar(value: value, tint: tint, height: 6, onChange: onChange)
        }
    }
}
