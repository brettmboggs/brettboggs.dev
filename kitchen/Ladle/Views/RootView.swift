import SwiftUI

enum RootTab: Hashable {
    case tonight
    case cookbook
    case pantry
    case shopping
    case plan
}

struct RootView: View {
    @Environment(Library.self) private var library
    @Environment(\.scenePhase) private var scenePhase

    @State private var tab: RootTab = .tonight
    @State private var cook = CookSession.shared
    @State private var showOnboarding = false
    @State private var reviewQueue: [RecipeDraft] = []
    @State private var notice: Notice?
    @State private var importing = false

    struct Notice: Identifiable {
        let id = UUID()
        let title: String
        let message: String
    }

    var body: some View {
        TabView(selection: $tab) {
            Tab("Tonight", systemImage: "sun.horizon", value: RootTab.tonight) {
                TonightView()
            }
            Tab("Cookbook", systemImage: "book", value: RootTab.cookbook) {
                NavigationStack { RecipesView() }
            }
            Tab("Pantry", systemImage: "cabinet", value: RootTab.pantry) {
                NavigationStack { PantryView() }
            }
            Tab("List", systemImage: "checklist", value: RootTab.shopping) {
                NavigationStack { ShoppingView() }
            }
            Tab("Plan", systemImage: "calendar", value: RootTab.plan) {
                NavigationStack { PlanView() }
            }
        }
        .fullScreenCover(isPresented: cookPresented) {
            CookView()
        }
        .sheet(isPresented: $showOnboarding) {
            OnboardingView()
                .interactiveDismissDisabled()
        }
        .sheet(item: currentReview) { draft in
            ImportReviewView(draft: draft)
        }
        .alert(item: $notice) { notice in
            Alert(title: Text(notice.title), message: Text(notice.message), dismissButton: .default(Text("OK")))
        }
        .overlay(alignment: .top) {
            if importing {
                HStack(spacing: 10) {
                    ProgressView()
                    Text("Reading the recipe…")
                        .font(Typeface.meta(12))
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(Capsule().fill(Ink.paperRaised))
                .padding(.top, 8)
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .onOpenURL { url in
            handle(url)
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { checkInbox() }
        }
        .onAppear {
            if !library.settings.hasOnboarded { showOnboarding = true }
            checkInbox()
        }
    }

    private var cookPresented: Binding<Bool> {
        Binding(
            get: { cook.isActive },
            set: { shown in if !shown { cook.end() } }
        )
    }

    private var currentReview: Binding<RecipeDraft?> {
        Binding(
            get: { reviewQueue.first },
            set: { value in
                if value == nil, !reviewQueue.isEmpty { reviewQueue.removeFirst() }
            }
        )
    }

    // MARK: - Arrivals

    private func handle(_ url: URL) {
        if url.isFileURL {
            do {
                let outcome = try FileImporter.importFile(at: url, into: library)
                switch outcome {
                case .recipes(let recipes):
                    if recipes.count == 1, let recipe = recipes.first {
                        notice = Notice(title: "Added to the Cookbook", message: "\(recipe.title) is in.")
                    } else {
                        notice = Notice(title: "Added to the Cookbook", message: "\(recipes.count) recipes are in.")
                    }
                case .library(let recipes, let pantry):
                    notice = Notice(title: "Cookbook restored", message: "\(recipes) recipes and \(pantry) pantry items were brought in.")
                }
                tab = .cookbook
            } catch {
                notice = Notice(title: "Could not open that", message: error.localizedDescription)
            }
            return
        }
        if url.scheme == "ladle" {
            let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
            if url.host() == "import",
               let raw = components?.queryItems?.first(where: { $0.name == "url" })?.value,
               let target = WebRecipeImporter.url(fromText: raw) {
                importFromWeb(target)
            } else if url.host() == "cook" || url.host() == "tonight" {
                tab = .tonight
            }
        }
    }

    private func checkInbox() {
        let urls = Inbox.take()
        for url in urls { importFromWeb(url) }
    }

    private func importFromWeb(_ url: URL) {
        withAnimation(.settle) { importing = true }
        Task {
            defer { withAnimation(.settle) { importing = false } }
            do {
                var draft = try await WebRecipeImporter.importRecipe(from: url)
                draft.recipe.needsReview = false
                reviewQueue.append(draft)
                Haptics.success()
            } catch {
                notice = Notice(title: "Could not import that link", message: error.localizedDescription)
            }
        }
    }
}
