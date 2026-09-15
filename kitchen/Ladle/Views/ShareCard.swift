import SwiftUI
import UIKit

/// The recipe laid out as a printed card: always black on white, whatever
/// the phone is set to, because it is going somewhere else.
struct RecipeCardView: View {
    let recipe: Recipe
    let system: UnitSystem
    var width: CGFloat = 390
    var photo: UIImage?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let photo {
                Image(uiImage: photo)
                    .resizable()
                    .scaledToFill()
                    .frame(width: width, height: width * 0.56)
                    .clipped()
            }
            VStack(alignment: .leading, spacing: 14) {
                Text(recipe.title)
                    .font(.system(size: 30, weight: .regular, design: .serif))
                    .fixedSize(horizontal: false, vertical: true)
                if !recipe.headnote.isBlank {
                    Text(recipe.headnote)
                        .font(.system(size: 14))
                        .foregroundStyle(Color(white: 0.35))
                        .fixedSize(horizontal: false, vertical: true)
                }
                if !recipe.metaLine.isEmpty {
                    Text(recipe.metaLine.uppercased())
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .tracking(1.4)
                        .foregroundStyle(Color(white: 0.35))
                }
                Rectangle().fill(Color.black).frame(height: 2)

                VStack(alignment: .leading, spacing: 6) {
                    label("Ingredients")
                    ForEach(recipe.ingredients) { ingredient in
                        if ingredient.isHeading {
                            Text(ingredient.name.uppercased())
                                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                                .tracking(1.2)
                                .foregroundStyle(Color(white: 0.35))
                                .padding(.top, 6)
                        } else {
                            Text(IngredientLine.text(ingredient, scale: 1, system: system))
                                .font(.system(size: 14))
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 10) {
                    label("Method")
                    let real = recipe.realSteps
                    ForEach(recipe.steps) { step in
                        if step.isHeading {
                            Text(step.text.uppercased())
                                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                                .tracking(1.2)
                                .foregroundStyle(Color(white: 0.35))
                                .padding(.top, 4)
                        } else if let index = real.firstIndex(where: { $0.id == step.id }) {
                            HStack(alignment: .firstTextBaseline, spacing: 10) {
                                Text(String(format: "%02d", index + 1))
                                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                                    .foregroundStyle(Color(white: 0.45))
                                    .frame(width: 22, alignment: .leading)
                                Text(step.text)
                                    .font(.system(size: 14))
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                }

                if !recipe.notes.isBlank {
                    VStack(alignment: .leading, spacing: 6) {
                        label("Notes")
                        Text(recipe.notes)
                            .font(.system(size: 13))
                            .foregroundStyle(Color(white: 0.3))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                HStack {
                    if let source = recipe.source.label {
                        Text("From \(source)")
                    }
                    Spacer()
                    Text("Ladle")
                }
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(Color(white: 0.5))
                .padding(.top, 10)
            }
            .padding(28)
        }
        .frame(width: width)
        .background(Color.white)
        .foregroundStyle(Color.black)
        .environment(\.colorScheme, .light)
        .dynamicTypeSize(.large)
    }

    private func label(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.system(size: 10, weight: .semibold, design: .monospaced))
            .tracking(1.6)
            .foregroundStyle(Color(white: 0.35))
    }
}

enum RecipeExport {
    /// A tall image of the card, sized for a message.
    @MainActor
    static func image(for recipe: Recipe, system: UnitSystem) -> UIImage? {
        let card = RecipeCardView(recipe: recipe, system: system, width: 390, photo: recipe.photoID.flatMap(PhotoStore.load))
        let renderer = ImageRenderer(content: card)
        renderer.scale = 3
        renderer.isOpaque = true
        return renderer.uiImage
    }

    /// US Letter pages, as many as it takes.
    @MainActor
    static func pdf(for recipe: Recipe, system: UnitSystem) -> URL? {
        let pageWidth: CGFloat = 612
        let pageHeight: CGFloat = 792
        let card = RecipeCardView(recipe: recipe, system: system, width: pageWidth, photo: recipe.photoID.flatMap(PhotoStore.load))

        let measure = ImageRenderer(content: card)
        measure.scale = 1
        guard let full = measure.uiImage else { return nil }
        let totalHeight = max(full.size.height, 1)
        let pages = max(1, Int(ceil(totalHeight / pageHeight)))

        let url = FileManager.default.temporaryDirectory.appendingPathComponent(Transfer.fileName(recipe.title, ext: "pdf"))
        var box = CGRect(x: 0, y: 0, width: pageWidth, height: pageHeight)
        guard let context = CGContext(url as CFURL, mediaBox: &box, nil) else { return nil }

        for page in 0..<pages {
            let slice = card
                .frame(width: pageWidth, height: totalHeight, alignment: .top)
                .offset(y: -CGFloat(page) * pageHeight)
                .frame(width: pageWidth, height: pageHeight, alignment: .top)
                .clipped()
                .background(Color.white)
            let renderer = ImageRenderer(content: slice)
            renderer.scale = 1
            context.beginPDFPage(nil)
            renderer.render { _, draw in
                draw(context)
            }
            context.endPDFPage()
        }
        context.closePDF()
        return url
    }
}
