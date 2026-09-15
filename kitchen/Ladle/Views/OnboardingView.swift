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
                    Text("All your recipes in one place.")
                        .font(Typeface.body(17))
                        .foregroundStyle(Ink.inkSoft)
                    Hairline()
                }
                .padding(.top, 24)

                point(symbol: "doc.viewfinder", title: "Scan the cards", text: "Point the camera at a recipe card or cookbook page. Check the text, then save.")
                point(symbol: "safari", title: "Save from Safari", text: "On a recipe website, tap Share, then Ladle.")
                point(symbol: "cabinet", title: "See what you can make", text: "Check off what you have. Ladle shows what you can make tonight.")
                point(symbol: "waveform", title: "Cook hands free", text: "Say \"next\", \"repeat\" or \"start timer\" while you cook.")

                VStack(spacing: 0) {
                    Toggle(isOn: $addStaples) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Start with common ingredients")
                                .font(Typeface.body(15, weight: .medium))
                            Text("Flour, eggs, onions, olive oil and about 50 more. You can change these later.")
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
                            Text("Sunday Pancakes, to try things out.")
                                .font(Typeface.body(13))
                                .foregroundStyle(Ink.inkSoft)
                        }
                    }
                    .padding(.vertical, 12)
                }
                .tint(Ink.accent)

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
