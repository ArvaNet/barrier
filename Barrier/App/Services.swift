import ActivityKit
import BackgroundTasks
import BarrierCore
import UIKit

// MARK: - Photos

/// Progress photos live only on this iPhone (and in its iCloud backup).
final class PhotoStore: @unchecked Sendable {
    private let fm = FileManager.default

    private var root: URL {
        let u = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Photos", isDirectory: true)
        try? fm.createDirectory(at: u, withIntermediateDirectories: true)
        return u
    }

    func url(_ id: String, thumb: Bool = false) -> URL {
        root.appendingPathComponent(thumb ? "\(id)-thumb.jpg" : "\(id).jpg")
    }

    /// Saves a full-size (max 2048px) and a thumbnail (max 480px) JPEG.
    func save(_ image: UIImage, id: String) throws {
        let full = image.resized(maxSide: 2048)
        let thumb = image.resized(maxSide: 480)
        guard let a = full.jpegData(compressionQuality: 0.86), let b = thumb.jpegData(compressionQuality: 0.8) else {
            throw CocoaError(.fileWriteUnknown)
        }
        try a.write(to: url(id), options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        try b.write(to: url(id, thumb: true), options: .atomic)
    }

    /// Write photo bytes as they are (restore), plus a fresh thumbnail.
    func saveData(_ data: Data, id: String) {
        try? data.write(to: url(id), options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        if let img = UIImage(data: data), let t = img.resized(maxSide: 480).jpegData(compressionQuality: 0.8) {
            try? t.write(to: url(id, thumb: true), options: .atomic)
        }
    }

    func image(_ id: String, thumb: Bool = false) -> UIImage? {
        UIImage(contentsOfFile: url(id, thumb: thumb).path) ?? (thumb ? UIImage(contentsOfFile: url(id).path) : nil)
    }

    func data(_ id: String) -> Data? { try? Data(contentsOf: url(id)) }

    func delete(_ id: String) {
        try? fm.removeItem(at: url(id))
        try? fm.removeItem(at: url(id, thumb: true))
    }

    func deleteAll() {
        try? fm.removeItem(at: root)
    }
}

extension UIImage {
    func resized(maxSide: CGFloat) -> UIImage {
        let longest = max(size.width, size.height)
        guard longest > maxSide else { return normalized() }
        let scale = maxSide / longest
        let target = CGSize(width: (size.width * scale).rounded(), height: (size.height * scale).rounded())
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        return UIGraphicsImageRenderer(size: target, format: format).image { _ in draw(in: CGRect(origin: .zero, size: target)) }
    }

    /// Bakes in the orientation so saved files display upright everywhere.
    func normalized() -> UIImage {
        guard imageOrientation != .up else { return self }
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = scale
        return UIGraphicsImageRenderer(size: size, format: format).image { _ in draw(in: CGRect(origin: .zero, size: size)) }
    }
}

// MARK: - Haptics

enum Haptics {
    static func tap(_ on: Bool = true) {
        guard on else { return }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    static func success(_ on: Bool = true) {
        guard on else { return }
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    static func soft(_ on: Bool = true) {
        guard on else { return }
        UIImpactFeedbackGenerator(style: .soft).impactOccurred()
    }
}

// MARK: - Live Activity (wait timer)

@MainActor
enum TimerActivity {
    private static var current: Activity<RitualTimerAttributes>?

    static func start(title: String, hue: Hue, reason: String, endsAt: Date, nextStep: String) {
        end()
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        let attrs = RitualTimerAttributes(title: title, hue: hue.rawValue, reason: reason)
        let state = RitualTimerAttributes.ContentState(endsAt: endsAt, nextStep: nextStep)
        current = try? Activity.request(attributes: attrs, content: .init(state: state, staleDate: endsAt.addingTimeInterval(60)))
    }

    /// Clean up a countdown left behind (app closed mid-wait, or already over).
    static func endStale(keepRunning: Bool) {
        let now = Date()
        for a in Activity<RitualTimerAttributes>.activities where !keepRunning || a.content.state.endsAt < now {
            Task { await a.end(nil, dismissalPolicy: .immediate) }
        }
    }

    static func end() {
        let all = Activity<RitualTimerAttributes>.activities
        current = nil
        Task {
            for a in all { await a.end(nil, dismissalPolicy: .immediate) }
        }
    }
}

// MARK: - Background refresh

/// Tops up the notification plan about once a day, even if the app isn't opened.
enum BackgroundRefresh {
    static var identifier: String { (Bundle.main.bundleIdentifier ?? "com.arvanet.barrier") + ".refresh" }

    static func register() {
        _ = BGTaskScheduler.shared.register(forTaskWithIdentifier: identifier, using: nil) { task in
            schedule()
            let work = Task { @MainActor in
                let model = AppModel.shared
                model.refreshClock()
                model.ingestInbox()
                await NotificationService.shared.reschedule(model.state)
                task.setTaskCompleted(success: true)
            }
            task.expirationHandler = { work.cancel() }
        }
    }

    static func schedule() {
        let req = BGAppRefreshTaskRequest(identifier: identifier)
        req.earliestBeginDate = Date().addingTimeInterval(8 * 3600)
        try? BGTaskScheduler.shared.submit(req)
    }
}
