import BarrierCore
import SwiftUI

struct RootView: View {
    @Environment(AppModel.self) private var model
    @State private var didLaunchRoute = false
    @State private var loadAlertDismissed = false

    var body: some View {
        @Bindable var model = model
        Group {
            if model.state.onboarded {
                MainTabs()
            } else {
                OnboardingView()
            }
        }
        .tint(Palette.ink)
        .toggleStyle(SageToggleStyle())
        .preferredColorScheme(model.state.settings.theme.scheme(at: model.now))
        .overlay(alignment: .bottom) {
            if let toast = model.toast {
                ToastView(toast: toast) { model.toast = nil }
                    .padding(.bottom, 64)
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.9), value: model.toast)
        .fullScreenCover(item: $model.ritual) { req in
            RitualView(request: req)
                .barrier(model)
        }
        .sheet(isPresented: $model.showSettings) {
            SettingsView().barrier(model)
        }
        .alert("Barrier couldn’t read your saved data", isPresented: Binding(
            get: { model.loadFailed && !loadAlertDismissed },
            set: { if !$0 { loadAlertDismissed = true } }
        )) {
            Button("Restore a backup") {
                loadAlertDismissed = true
                model.showSettings = true
            }
            Button("Start fresh", role: .destructive) {
                loadAlertDismissed = true
                model.acceptFreshStart()
            }
        } message: {
            Text("Nothing has been deleted: the unreadable file is kept on this iPhone. Restore a backup file if you have one, or start fresh.")
        }
        .onAppear(perform: applyLaunchScreen)
    }

    /// `-screen progress` etc., for screenshots.
    private func applyLaunchScreen() {
        guard !didLaunchRoute, let screen = model.launch.screen else { return }
        didLaunchRoute = true
        switch screen {
        case "routine", "routine-body", "routine-history", "step-editor", "add-product", "pause": model.tab = .routine
        case "ritual-body": model.open(.ritual(.body, model.today))
        case "progress", "progress-bottom": model.tab = .progress
        case "derm", "procedure", "procedure-compare", "sample-report", "procedure-new": model.tab = .derm
        case "report", "report-photos", "report-routine": model.open(.report)
        case "settings": model.showSettings = true
        case "ritual", "ritual-wait", "ritual-done": model.open(.ritual(.pm, model.today))
        case "ritual-am": model.open(.ritual(.am, model.today))
        default: break
        }
    }
}

struct MainTabs: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        TabView(selection: $model.tab) {
            TodayView()
                .tabItem { Label("Today", systemImage: "sun.horizon") }
                .tag(AppTab.today)
            RoutineView()
                .tabItem { Label("Routine", systemImage: "list.bullet.rectangle") }
                .tag(AppTab.routine)
            ProgressScreen()
                .tabItem { Label("Progress", systemImage: "chart.line.uptrend.xyaxis") }
                .tag(AppTab.progress)
            DermView()
                .tabItem { Label("Derm", systemImage: "stethoscope") }
                .tag(AppTab.derm)
        }
    }
}

/// A scrollable page with the app's background.
struct Page<Content: View>: View {
    @Environment(AppModel.self) private var model
    var spacing: CGFloat = 12
    @ViewBuilder var content: () -> Content

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: spacing) {
                    content()
                    Color.clear.frame(height: 1).id("page-bottom")
                }
                // 16 pt: the same edge as the inset lists on the other tabs.
                .padding(.horizontal, 16)
                .padding(.top, 4)
                .padding(.bottom, 32)
                .frame(maxWidth: 560)
                .frame(maxWidth: .infinity)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(Palette.bg.ignoresSafeArea())
            .onAppear {
                // Screenshot hook: `-screen today-bottom`.
                if model.launch.screen?.hasSuffix("-bottom") == true {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { proxy.scrollTo("page-bottom", anchor: .bottom) }
                }
                // `-screen today-procedure`, `-screen today-score`: that card at the top.
                if let screen = model.launch.screen, screen.hasPrefix("today-"), !screen.hasSuffix("-bottom") {
                    let id = String(screen.dropFirst("today-".count))
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { proxy.scrollTo(id, anchor: .top) }
                }
            }
        }
    }
}
