import BarrierCore
import Foundation

/// Files shared by the app, the widget and the intents (via the App Group).
/// The app owns state.json. Other processes never write it; they append taps
/// to inbox.json, which the app folds in when it next becomes active.
enum SharedStore {
    static var groupID: String {
        (Bundle.main.object(forInfoDictionaryKey: "BarrierAppGroup") as? String) ?? "group.com.arvanet.barrier"
    }

    /// True when the App Group works, so the widget sees the same data.
    static var isShared: Bool {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: groupID) != nil
    }

    static var container: URL {
        if let u = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: groupID) {
            return u
        }
        let u = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Barrier", isDirectory: true)
        try? FileManager.default.createDirectory(at: u, withIntermediateDirectories: true)
        return u
    }

    static var stateURL: URL { container.appendingPathComponent("state.json") }
    static var inboxURL: URL { container.appendingPathComponent("inbox.json") }

    /// Darwin notification posted after an inbox write, so a running app can react.
    static let inboxNotification = "com.arvanet.barrier.inbox"

    // MARK: State

    enum LoadResult {
        /// First launch: nothing saved yet.
        case empty
        case loaded(AppState)
        /// A file exists but couldn't be read (locked before first unlock, or damaged).
        case failed
    }

    static func load() -> LoadResult {
        guard FileManager.default.fileExists(atPath: stateURL.path) else { return .empty }
        guard let data = coordinatedRead(stateURL) else { return .failed }
        do {
            return .loaded(try StateCoder.decode(data))
        } catch {
            keepCopy(data)
            return .failed
        }
    }

    static func loadState() -> AppState? {
        if case .loaded(let s) = load() { return s }
        return nil
    }

    /// Keep an unreadable file aside so nothing is ever silently lost.
    private static func keepCopy(_ data: Data) {
        let stamp = Int(Date().timeIntervalSince1970)
        let url = container.appendingPathComponent("state.unreadable-\(stamp).json")
        try? data.write(to: url, options: .atomic)
    }

    static func saveState(_ s: AppState) throws {
        let data = try StateCoder.encode(s)
        var failure: Error?
        coordinatedWrite(stateURL) { url in
            do { try data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication]) } catch { failure = error }
        }
        if let failure { throw failure }
    }

    // MARK: Inbox

    static func appendInbox(_ item: InboxItem) {
        coordinatedWrite(inboxURL) { url in
            var items = (try? Data(contentsOf: url)).flatMap { try? StateCoder.decoder().decode([InboxItem].self, from: $0) } ?? []
            items.append(item)
            if let data = try? StateCoder.encoder().encode(items) {
                try? data.write(to: url, options: .atomic)
            }
        }
        postInboxNotification()
    }

    static func peekInbox() -> [InboxItem] {
        guard let data = coordinatedRead(inboxURL) else { return [] }
        return (try? StateCoder.decoder().decode([InboxItem].self, from: data)) ?? []
    }

    static func drainInbox() -> [InboxItem] {
        var items: [InboxItem] = []
        coordinatedWrite(inboxURL) { url in
            if let data = try? Data(contentsOf: url) {
                items = (try? StateCoder.decoder().decode([InboxItem].self, from: data)) ?? []
            }
            try? FileManager.default.removeItem(at: url)
        }
        return items
    }

    /// State with pending inbox taps applied: what the widget should show.
    static func currentState(today: Day = Day.routineDay()) -> AppState? {
        guard var s = loadState() else { return nil }
        let inbox = peekInbox()
        if !inbox.isEmpty { s.apply(inbox, today: today) }
        return s
    }

    // MARK: Plumbing

    private static func coordinatedRead(_ url: URL) -> Data? {
        var out: Data?
        var err: NSError?
        NSFileCoordinator(filePresenter: nil).coordinate(readingItemAt: url, options: [], error: &err) { u in
            out = try? Data(contentsOf: u)
        }
        return out
    }

    private static func coordinatedWrite(_ url: URL, _ body: (URL) -> Void) {
        var err: NSError?
        NSFileCoordinator(filePresenter: nil).coordinate(writingItemAt: url, options: .forMerging, error: &err) { u in
            body(u)
        }
    }

    static func postInboxNotification() {
        CFNotificationCenterPostNotification(
            CFNotificationCenterGetDarwinNotifyCenter(),
            CFNotificationName(inboxNotification as CFString), nil, nil, true
        )
    }
}
