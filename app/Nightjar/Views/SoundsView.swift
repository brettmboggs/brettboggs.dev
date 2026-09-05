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
            HStack(alignment: .firstTextBaseline) {
                SectionLabel(
                    "Playing",
                    trailing: "\(player.currentMix.layers.count) of \(player.plan.maximumLayers)"
                )
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

                HStack(spacing: 10) {
                    if let remaining = player.previewRemaining {
                        Chip(text: "Preview · \(Format.clock(remaining))", systemImage: "sparkles")
                    }
                    Spacer()
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
                    SoftButton(title: "Clear", systemImage: "xmark") {
                        player.clearMix()
                    }
                }
                .padding(.top, 12)
            }
        }
        .animation(.settle, value: player.currentMix.layers.count)
    }

    // MARK: - Shelves

    private func shelf(title: String, sounds: [SoundKind]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionLabel(title)
                .padding(.top, 30)
                .padding(.bottom, 4)
            ForEach(sounds) { kind in
                SoundRow(kind: kind) { shapingSound = kind }
                Hairline()
            }
        }
    }
}

// MARK: - Rows

/// One sound on the shelf. Tap to add or remove; long press to star.
struct SoundRow: View {
    @Environment(PlayerController.self) private var player
    let kind: SoundKind
    let onShape: () -> Void

    var body: some View {
        let isActive = player.isActive(kind.id)
        let isLocked = !player.plan.allows(kind)

        Button {
            player.toggleSound(kind)
        } label: {
            IndexRow(title: kind.name, detail: kind.blurb, isActive: isActive) {
                HStack(spacing: 12) {
                    if isLocked { PlusMark() }
                    if player.isFavourite(kind.id) {
                        Image(systemName: "star.fill")
                            .font(.system(size: 10))
                            .foregroundStyle(Palette.ember.opacity(0.8))
                    }
                    if isActive {
                        OrbMark(size: 18, isLit: true)
                    } else {
                        Image(systemName: "plus")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Palette.inkFaint)
                            .frame(width: 18, height: 18)
                    }
                }
            }
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button {
                player.toggleFavourite(kind.id)
            } label: {
                Label(player.isFavourite(kind.id) ? "Unstar" : "Star", systemImage: "star")
            }
            if isActive {
                Button { onShape() } label: { Label("Shape", systemImage: "slider.horizontal.3") }
            }
        }
    }
}

/// One layer of the running mix, with its fader inline.
struct LayerRow: View {
    @Environment(PlayerController.self) private var player
    let layer: Layer
    let onShape: () -> Void

    var body: some View {
        let tint = layer.kind.map { Palette.tint(for: $0.family) } ?? Palette.ember
        VStack(spacing: 2) {
            HStack(spacing: 10) {
                Text(layer.name)
                    .font(Typeface.body(15, weight: .medium))
                    .foregroundStyle(layer.isMuted ? Palette.inkFaint : Palette.ink)
                Spacer()
                Button { onShape() } label: {
                    Image(systemName: "slider.horizontal.3")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Palette.inkSoft)
                        .frame(width: 30, height: 30)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                Button { player.toggleMute(layer.soundID) } label: {
                    Image(systemName: layer.isMuted ? "speaker.slash" : "speaker.wave.2")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Palette.inkSoft)
                        .frame(width: 30, height: 30)
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

            HStack {
                SoftButton(title: player.isFavourite(kind.id) ? "Starred" : "Star", systemImage: "star") {
                    player.toggleFavourite(kind.id)
                }
                Spacer()
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
