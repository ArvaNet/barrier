import AppIntents
import BarrierCore
import SwiftUI

final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        NotificationService.shared.configure()
        BackgroundRefresh.register()
        return true
    }
}

@main
struct BarrierApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @Environment(\.scenePhase) private var scenePhase
    @State private var model = AppModel.shared

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
                .onOpenURL { model.handle(link: $0.absoluteString) }
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active:
                model.becameActive()
            case .background:
                model.saveNow()
                BackgroundRefresh.schedule()
            default:
                break
            }
        }
    }
}

/// Siri and Shortcuts phrases.
struct BarrierShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: MarkRoutineDoneIntent(),
            phrases: ["Mark my \(.applicationName) routine done", "I did my \(.applicationName) routine"],
            shortTitle: "Routine done",
            systemImageName: "checkmark.circle"
        )
        AppShortcut(
            intent: TonightIntent(),
            phrases: ["What’s tonight in \(.applicationName)", "What’s my \(.applicationName) routine tonight"],
            shortTitle: "Tonight",
            systemImageName: "moon.stars"
        )
    }
}
