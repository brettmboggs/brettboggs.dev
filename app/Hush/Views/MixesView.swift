import SwiftUI

struct MixesView: View {
    @Environment(PlayerController.self) private var player
    @State private var showSave = false
    @State private var saveName = ""
    @State private var renaming: Mix?
    @State private var renameText = ""

    var body: some View {
        ZStack {
            Palette.ground.ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 26) {
                    heading
                    actions

                    section(
                        title: "Yours",
                        mixes: player.library.userMixes.sorted { $0.createdAt > $1.createdAt },
                        emptyText: "Nothing saved yet. Build something on Now and save it."
                    )

                    section(title: "Starting points", mixes: Mix.presets, emptyText: nil)
                }
                .pageGutter()
                .padding(.top, 8)
                .padding(.bottom, 40)
            }
        }
        .alert("Save this mix", isPresented: $showSave) {
            TextField("Name", text: $saveName)
            Button("Save") {
                player.saveCurrentMix(named: saveName)
                saveName = ""
            }
            Button("Cancel", role: .cancel) { saveName = "" }
        }
        .alert("Rename", isPresented: Binding(
            get: { renaming != nil },
            set: { if !$0 { renaming = nil } }
        )) {
            TextField("Name", text: $renameText)
            Button("Save") {
                if let mix = renaming {
                    player.library.rename(mix, to: renameText)
                }
                renaming = nil
            }
            Button("Cancel", role: .cancel) { renaming = nil }
        }
    }

    private var heading: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Mixes")
                .font(Typeface.display(32))
                .foregroundStyle(Palette.ink)
            Text(player.currentMix.isEmpty
                 ? "Nothing playing."
                 : "Playing \(player.currentMix.name).")
                .font(Typeface.body(13))
                .foregroundStyle(Palette.inkFaint)
        }
        .padding(.top, 14)
    }

    private var actions: some View {
        HStack(spacing: 10) {
            SoftButton(
                title: "Save current",
                systemImage: "square.and.arrow.down",
                isProminent: true
            ) {
                saveName = player.currentMix.name
                showSave = true
            }
            .disabled(player.currentMix.isEmpty)
            .opacity(player.currentMix.isEmpty ? 0.4 : 1)

            SoftButton(title: "Surprise me", systemImage: "dice") {
                player.surpriseMe()
            }
            Spacer()
        }
    }

    @ViewBuilder
    private func section(title: String, mixes: [Mix], emptyText: String?) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionLabel(title, trailing: mixes.isEmpty ? nil : "\(mixes.count)")
                .padding(.bottom, 8)

            if mixes.isEmpty {
                if let emptyText {
                    Text(emptyText)
                        .font(Typeface.body(13))
                        .foregroundStyle(Palette.inkFaint)
                        .padding(.vertical, 14)
                }
            } else {
                ForEach(mixes) { mix in
                    mixRow(mix)
                    if mix.id != mixes.last?.id { Hairline() }
                }
            }
        }
    }

    private func mixRow(_ mix: Mix) -> some View {
        let isCurrent = mix.id == player.currentMix.id

        return Button {
            player.load(mix)
            if !player.isPlaying { player.play() }
        } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(mix.name)
                        .font(Typeface.display(21))
                        .foregroundStyle(isCurrent ? Palette.ember : Palette.ink)
                    Text(mix.summary)
                        .font(Typeface.meta(10))
                        .tracking(0.8)
                        .foregroundStyle(Palette.inkFaint)
                        .lineLimit(1)
                }

                Spacer(minLength: 8)

                if isCurrent && player.isPlaying {
                    PulseDot(isActive: true, level: player.meterLevel)
                }

                Menu {
                    Button {
                        player.load(mix)
                        player.play()
                    } label: {
                        Label("Play", systemImage: "play")
                    }
                    if !mix.isBuiltIn {
                        Button {
                            renameText = mix.name
                            renaming = mix
                        } label: {
                            Label("Rename", systemImage: "pencil")
                        }
                        Button(role: .destructive) {
                            player.library.delete(mix)
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Palette.inkFaint)
                        .frame(width: 30, height: 30)
                        .contentShape(Rectangle())
                }
            }
            .padding(.vertical, 14)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
