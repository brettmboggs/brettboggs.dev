import SwiftUI

/// Three sentences and two switches. Shown once.
struct OnboardingView: View {
    @Environment(Library.self) private var library
    @Environment(\.dismiss) private var dismiss

    @State private var addStaples = true
    @State private var addSample = true

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Ladle")
                        .font(Typeface.display(52))
                    Text("Every recipe you have, in one place, ready to cook from.")
                        .font(Typeface.body(17))
                        .foregroundStyle(Ink.inkSoft)
                    Rule()
                }
                .padding(.top, 24)

                point(symbol: "doc.viewfinder", title: "Scan the cards", text: "Point the camera at a handwritten card or a cookbook page. The words are read on the phone and laid out cleanly. You check them, then they are yours.")
                point(symbol: "safari", title: "Save from Safari", text: "On any recipe page, tap Share, then Ladle. It arrives formatted like everything else.")
                point(symbol: "cabinet", title: "Know what you can cook", text: "Tell the pantry what is in the kitchen. Tonight shows what is ready, what is one ingredient away, and what to swap.")
                point(symbol: "waveform", title: "Cook without touching", text: "Say \"next\" to move on, \"repeat\" to hear it again, \"start timer\" when the step says twenty minutes.")

                VStack(spacing: 0) {
                    Toggle(isOn: $addStaples) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Stock the pantry with the usual things")
                                .font(Typeface.body(15, weight: .medium))
                            Text("Flour, eggs, onions, olive oil and about fifty more. Easy to trim.")
                                .font(Typeface.body(13))
                                .foregroundStyle(Ink.inkSoft)
                        }
                    }
                    .padding(.vertical, 12)
                    Hairline()
                    Toggle(isOn: $addSample) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Add a sample recipe")
                                .font(Typeface.body(15, weight: .medium))
                            Text("Sunday Pancakes, so there is something to look at.")
                                .font(Typeface.body(13))
                                .foregroundStyle(Ink.inkSoft)
                        }
                    }
                    .padding(.vertical, 12)
                }
                .tint(Ink.ink)

                InkButton(title: "Start cooking") {
                    library.completeOnboarding(addStaples: addStaples, addSample: addSample)
                    Haptics.success()
                    dismiss()
                }
                .padding(.bottom, 24)
            }
            .padding(.horizontal, 24)
        }
        .background(Ink.paper)
    }

    private func point(symbol: String, title: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 16) {
            Image(systemName: symbol)
                .font(.system(size: 22, weight: .light))
                .frame(width: 32)
                .padding(.top, 2)
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(Typeface.display(21))
                Text(text)
                    .font(Typeface.body(15))
                    .foregroundStyle(Ink.inkSoft)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
