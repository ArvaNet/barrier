import BarrierCore
import SwiftUI

struct RootView: View {
    @Environment(AppModel.self) private var model
    @State private var didLaunchRoute = false

    var body: some View {
        @Bindable var model = model
        Group {
            if model.state.onboarded {
                MainTabs()
            } else {
                OnboardingView()
            }
        }
        .tint(Palette.accent)
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
                .environment(model)
        }
        .sheet(isPresented: $model.showSettings) {
            SettingsView().environment(model)
        }
        .onAppear(perform: applyLaunchScreen)
    }

    /// `-screen progress` etc., for screenshots.
    private func applyLaunchScreen() {
        guard !didLaunchRoute, let screen = model.launch.screen else { return }
        didLaunchRoute = true
        switch screen {
        case "routine": model.tab = .routine
        case "progress": model.tab = .progress
        case "derm": model.tab = .derm
        case "report": model.open(.report)
        case "settings": model.showSettings = true
        case "ritual": model.open(.ritual(.pm, model.today))
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
                .tag(Tab.today)
            RoutineView()
                .tabItem { Label("Routine", systemImage: "list.bullet.rectangle") }
                .tag(Tab.routine)
            ProgressScreen()
                .tabItem { Label("Progress", systemImage: "circle.circle") }
                .tag(Tab.progress)
            DermView()
                .tabItem { Label("Derm", systemImage: "stethoscope") }
                .tag(Tab.derm)
        }
    }
}

/// A scrollable page with the app's background.
struct Page<Content: View>: View {
    var spacing: CGFloat = 16
    @ViewBuilder var content: () -> Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: spacing) {
                content()
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 40)
            .frame(maxWidth: 560)
            .frame(maxWidth: .infinity)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(Palette.bg.ignoresSafeArea())
    }
}
