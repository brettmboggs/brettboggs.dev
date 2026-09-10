import SwiftUI

/// The library and the mix, on one screen. Rows, not tiles.
struct SoundsView: View {
    @Environment(PlayerController.self) private var player

    @State private var shapingSound: SoundKind?
    @State private var showMixes = false
    @State private var showSave = false
    @State private var saveName = ""

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                ScreenTitle(title: "Sounds", subtitle: "\(SoundCatalog.all.count) of them. Two of them loop.") {
                    IconButton(systemImage: "rectangle.stack") { showMixes = true }
                        .padding(.top, 6)
                }
                .padding(.top, 8)

                currentMix
                    .padding(.top, 22)

                if !favourites.isEmpty {
                    shelf(title: "Starred", sounds: favourites)
                }
                ForEach(SoundCatalog.shelves, id: \.family) { shelf in
                    self.shelf(title: shelf.family.title, sounds: shelf.sounds)
                }

                Color.clear.frame(height: 96)
            }
            .pageGutter()
        }
        .onAppear {
            #if DEBUG
            if Demo.sheet == "mixes" { showMixes = true }
            #endif
        }
        .sheet(item: $shapingSound) { kind in ShapingSheet(kind: kind) }
        .sheet(isPresented: $showMixes) { MixesSheet() }
        .alert("Name this mix", isPresented: $showSave) {
            TextField("Name", text: $saveName)
            Button("Save") {
                player.saveCurrentMix(named: saveName)
                saveName = ""
            }
            Button("Cancel", role: .cancel) { saveName = "" }
        } message: {
            Text("It will show up under your mixes.")
        }
    }

    private var favourites: [SoundKind] {
        SoundCatalog.all.filter { player.isFavourite($0.id) }
    }

    // MARK: - The mix

    private var currentMix: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                SectionLabel(
                    "Playing",
                    trailing: "\(player.currentMix.layers.count) of \(player.plan.maximumLayers)"
                )
                if !player.currentMix.isEmpty {
                    Button { player.clearMix() } label: {
                        Text("CLEAR")
                            .font(Typeface.meta(10, weight: .semibold))
                            .tracking(1.4)
                            .foregroundStyle(Palette.inkFaint)
                    }
                    .buttonStyle(.plain)
                }
            }
            if player.currentMix.isEmpty {
                QuietNotice(text: "Tap a sound below. Two at once is free.")
            } else {
                VStack(spacing: 0) {
                    ForEach(player.currentMix.layers) { layer in
                        LayerRow(layer: layer) { shapingSound = layer.kind }
                        Hairline()
                    }
                }
                .padding(.top, 6)

                // Only what is true right now: a preview counting down, or a
                // mix that has drifted and could be kept. Usually neither, and
                // then this row is not there at all.
                if player.previewRemaining != nil || player.currentMixIsUnsaved {
                    HStack(spacing: 10) {
                        if let remaining = player.previewRemaining {
                            Chip(text: "Preview · \(Format.clock(remaining))", systemImage: "sparkles")
                        }
                        Spacer(minLength: 0)
                        if player.currentMixIsUnsaved {
                            SoftButton(title: "Save mix", systemImage: "bookmark") {
                                if player.canSaveAnotherMix {
                                    saveName = player.currentMix.name
                                    showSave = true
                                } else {
                                    player.requestUpgrade(.mixes)
                                }
                            }
                        }
                    }
                    .padding(.top, 12)
                }
            }
        }
        .animation(.settle, value: player.currentMix.layers.count)
    }

    // MARK: - Shelves

    /// Two columns of names, and nothing else.
    ///
    /// This used to be one column of name, blurb, badge and a plus button:
    /// thirty-five rows of four things each, which is a database browser and
    /// not a shelf. The blurbs were good writing in the wrong place, so they
    /// moved to the sheet you get when you shape a sound. What is left is the
    /// thing you came for, which is the name, at a size you can hit in the
    /// dark.
    private func shelf(title: String, sounds: [SoundKind]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionLabel(title)
                .padding(.top, 26)
                .padding(.bottom, 2)
            LazyVGrid(
                columns: [
                    GridItem(.flexible(), spacing: 14, alignment: .leading),
                    GridItem(.flexible(), spacing: 14, alignment: .leading),
                ],
                spacing: 0
            ) {
                ForEach(sounds) { kind in
                    SoundName(kind: kind)
                }
            }
        }
    }
}

// MARK: - Rows

/// One name on the shelf. Tap to add or remove.
///
/// Every other affordance this row used to carry is gone: the blurb, the plus
/// button, the star, the badge. A sound is either on or it is not, and the
/// only thing that says so is the colour of its name and a dot beside it.
/// Locked ones are dimmed rather than labelled, because a shelf of PLUS
/// badges is an advertisement, not a shelf. Tapping one still opens the ask.
struct SoundName: View {
    @Environment(PlayerController.self) private var player
    let kind: SoundKind

    var body: some View {
        let isActive = player.isActive(kind.id)
        let isLocked = !player.plan.allows(kind)

        Button {
            player.toggleSound(kind)
        } label: {
            HStack(spacing: 9) {
                Circle()
                    .fill(isActive ? Palette.ember : Color.clear)
                    .frame(width: 6, height: 6)
                Text(kind.name)
                    .font(Typeface.body(16, weight: isActive ? .medium : .regular))
                    .foregroundStyle(
                        isActive ? Palette.ember : (isLocked ? Palette.inkFaint : Palette.ink)
                    )
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Spacer(minLength: 0)
            }
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button {
                player.toggleFavourite(kind.id)
            } label: {
                Label(player.isFavourite(kind.id) ? "Unstar" : "Star", systemImage: "star")
            }
        }
        .accessibilityLabel(kind.name)
        .accessibilityValue(isActive ? "Playing" : (isLocked ? "Part of Plus" : "Off"))
        .accessibilityHint(kind.blurb)
    }
}

/// One layer of the running mix.
///
/// It used to carry four controls: shape, mute, remove and the fader. Three
/// of them were doing the same job from different directions. The name is now
/// the button, it opens the sheet where mute and remove already live, and
/// what is left on the row is the one thing worth reaching for in the dark.
struct LayerRow: View {
    @Environment(PlayerController.self) private var player
    let layer: Layer
    let onShape: () -> Void

    var body: some View {
        let tint = layer.kind.map { Palette.tint(for: $0.family) } ?? Palette.ember
        VStack(spacing: 2) {
            HStack(spacing: 10) {
                Button { onShape() } label: {
                    HStack(spacing: 7) {
                        Text(layer.name)
                            .font(Typeface.body(15, weight: .medium))
                            .foregroundStyle(layer.isMuted ? Palette.inkFaint : Palette.ink)
                        if layer.isMuted {
                            Image(systemName: "speaker.slash")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(Palette.inkFaint)
                        }
                        Spacer(minLength: 0)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                Button { player.remove(soundID: layer.soundID) } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Palette.inkFaint)
                        .frame(width: 30, height: 30)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Remove \(layer.name)")
            }
            .padding(.top, 8)
            FaderBar(value: layer.level, tint: tint) { value in
                player.setLevel(value, for: layer.soundID)
            }
            .opacity(layer.isMuted ? 0.4 : 1)
        }
    }
}

// MARK: - Shaping

/// Level and the two per-sound controls, in a half sheet.
struct ShapingSheet: View {
    @Environment(PlayerController.self) private var player
    @Environment(\.dismiss) private var dismiss
    let kind: SoundKind

    var body: some View {
        let layer = player.currentMix.layer(for: kind.id) ?? Layer(kind: kind)
        let tint = Palette.tint(for: kind.family)

        VStack(alignment: .leading, spacing: 0) {
            SheetHeader(title: kind.name, subtitle: kind.blurb, onClose: { dismiss() })

            control(label: "Level", value: layer.level, tint: tint) { value in
                player.setLevel(value, for: kind.id)
            }
            .padding(.top, 24)
            control(label: kind.toneLabel, value: layer.tone, tint: tint) { value in
                player.setTone(value, for: kind.id)
            }
            control(label: kind.motionLabel, value: layer.motion, tint: tint) { value in
                player.setMotion(value, for: kind.id)
            }

            HStack(spacing: 10) {
                SoftButton(
                    title: layer.isMuted ? "Unmute" : "Mute",
                    systemImage: layer.isMuted ? "speaker.slash" : "speaker.wave.2"
                ) {
                    player.toggleMute(kind.id)
                }
                SoftButton(title: player.isFavourite(kind.id) ? "Starred" : "Star", systemImage: "star") {
                    player.toggleFavourite(kind.id)
                }
                Spacer(minLength: 0)
                SoftButton(title: "Remove", systemImage: "xmark") {
                    player.remove(soundID: kind.id)
                    dismiss()
                }
            }
            .padding(.top, 22)

            Spacer(minLength: 16)
        }
        .pageGutter()
        .sheetDressing()
        .presentationDetents([.height(420)])
        .paywallHost()
    }

    private func control(label: String, value: Double, tint: Color, onChange: @escaping (Double) -> Void) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            SectionLabel(label, trailing: "\(Int(value * 100))")
            FaderBar(value: value, tint: tint, onChange: onChange)
        }
        .padding(.bottom, 8)
    }
}

// MARK: - Mixes

struct MixesSheet: View {
    @Environment(PlayerController.self) private var player
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                SheetHeader(
                    title: "Mixes",
                    subtitle: player.plan.isPlus
                        ? "Yours, then the starting points."
                        : "Two saved mixes are free.",
                    onClose: { dismiss() }
                )

                if !player.library.userMixes.isEmpty {
                    SectionLabel("Yours", trailing: player.plan.isPlus ? nil : "\(player.library.userMixes.count) of \(Plan.freeSavedMixes)")
                        .padding(.top, 26)
                    ForEach(player.library.userMixes.sorted { $0.createdAt > $1.createdAt }) { mix in
                        row(mix)
                    }
                }

                SectionLabel("Starting points")
                    .padding(.top, 26)
                ForEach(Mix.presets) { mix in
                    row(mix)
                }

                Color.clear.frame(height: 30)
            }
            .pageGutter()
        }
        .sheetDressing()
        .paywallHost()
    }

    private func row(_ mix: Mix) -> some View {
        let isCurrent = player.currentMix.id == mix.id
        let locked = !mix.usesOnlyFreeSounds && !player.plan.isPlus
        return VStack(spacing: 0) {
            Button {
                player.load(mix)
                if !player.isPlaying { player.play() }
                dismiss()
            } label: {
                IndexRow(title: mix.name, detail: mix.summary, isActive: isCurrent) {
                    HStack(spacing: 10) {
                        if locked { PlusMark() }
                        if isCurrent { OrbMark(size: 18, isLit: true) }
                    }
                }
            }
            .buttonStyle(.plain)
            .contextMenu {
                if !mix.isBuiltIn {
                    Button(role: .destructive) {
                        player.library.delete(mix)
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
            }
            Hairline()
        }
    }
}
