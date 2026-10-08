import BarrierCore
import SwiftUI
import UniformTypeIdentifiers
import UserNotifications

struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @State private var exportURL: URL?
    @State private var importing = false
    @State private var pendingImport: Backup?
    @State private var confirmReset = false

    var body: some View {
        let s = model.state.settings
        NavigationStack {
            Form {
                remindersSection(s)
                Section("Appearance") {
                    Picker("Theme", selection: Binding(get: { s.theme }, set: { v in model.update { $0.settings.theme = v } })) {
                        ForEach(ThemeMode.allCases) { Text($0.label).tag($0) }
                    }
                    Toggle("Haptics", isOn: Binding(get: { s.haptics }, set: { v in model.update { $0.settings.haptics = v } }))
                }
                Section {
                    Picker("Weekly photo night", selection: Binding(get: { s.photoDay }, set: { v in model.update { $0.settings.photoDay = v } })) {
                        Text("Off").tag(-1)
                        ForEach([1, 2, 3, 4, 5, 6, 0], id: \.self) { d in Text(Calendar.current.weekdaySymbols[d]).tag(d) }
                    }
                } footer: {
                    Text("That night’s reminder adds “photo night”, and Today asks for a photo.")
                }
                dataSection
                Section("About") {
                    LabeledContent("Version", value: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0")
                    Text(Guidance.disclaimer).font(.footnote).foregroundStyle(.secondary)
                    Text("Your routine, photos and notes stay on this iPhone. Nothing is sent anywhere.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .fileImporter(isPresented: $importing, allowedContentTypes: [.json]) { result in
                guard case .success(let url) = result else { return }
                let access = url.startAccessingSecurityScopedResource()
                defer { if access { url.stopAccessingSecurityScopedResource() } }
                if let data = try? Data(contentsOf: url), let b = try? Backup.decode(data) {
                    pendingImport = b
                } else {
                    model.show("That file isn’t a Barrier backup.")
                }
            }
            .confirmationDialog("Replace everything with this backup?", isPresented: Binding(get: { pendingImport != nil }, set: { if !$0 { pendingImport = nil } }), titleVisibility: .visible) {
                Button("Replace", role: .destructive) {
                    if let b = pendingImport { b.restore(into: model) }
                    pendingImport = nil
                }
            } message: {
                Text("Your current routine, history and photos on this iPhone will be replaced.")
            }
            .confirmationDialog("Erase everything?", isPresented: $confirmReset, titleVisibility: .visible) {
                Button("Erase all data", role: .destructive) {
                    model.resetEverything()
                    dismiss()
                }
            } message: {
                Text("Routine, history, photos and notes. This can’t be undone. Export a backup first if you might want them.")
            }
        }
        .task { await model.refreshNotificationStatus() }
    }

    @ViewBuilder
    private func remindersSection(_ s: Settings) -> some View {
        Section {
            switch model.notificationStatus {
            case .denied:
                VStack(alignment: .leading, spacing: 6) {
                    Label("Notifications are off for Barrier", systemImage: "bell.slash").font(.subheadline.weight(.semibold))
                    Text("Turn them on in iPhone Settings so reminders can reach you.").font(.footnote).foregroundStyle(.secondary)
                }
                Button("Open iPhone Settings") {
                    if let url = URL(string: UIApplication.openNotificationSettingsURLString) { openURL(url) }
                }
            case .notDetermined:
                Button("Turn on reminders") {
                    Task {
                        await NotificationService.shared.requestAuthorization()
                        await model.refreshNotificationStatus()
                        model.scheduleNotifications(immediately: true)
                    }
                }
            default:
                Toggle("Reminders", isOn: Binding(get: { s.remindersOn }, set: { v in
                    model.update { $0.settings.remindersOn = v }
                    if !v { Task { await NotificationService.shared.removeAll() } }
                }))
                if s.remindersOn {
                    Toggle("Gentle nudge if not done", isOn: Binding(get: { s.nudge }, set: { v in model.update { $0.settings.nudge = v } }))
                    if s.nudge {
                        Picker("Nudge after", selection: Binding(get: { s.nudgeAfterMin }, set: { v in model.update { $0.settings.nudgeAfterMin = v } })) {
                            ForEach([20, 30, 45, 60, 90], id: \.self) { Text("\($0) min").tag($0) }
                        }
                    }
                    Toggle("Midday sunscreen top-up", isOn: Binding(get: { s.spfMidday }, set: { v in model.update { $0.settings.spfMidday = v } }))
                    if s.spfMidday {
                        DatePicker("At", selection: Binding(get: { s.spfTime.date }, set: { d in model.update { $0.settings.spfTime = ClockTime(date: d) } }), displayedComponents: .hourAndMinute)
                    }
                    Button("Send a test reminder") {
                        NotificationService.shared.sendTest()
                        model.show("Coming in 5 seconds. Lock your phone to see it.")
                    }
                }
            }
        } header: {
            Text("Reminders")
        } footer: {
            Text("Times are set per routine in the Routine tab. Long-press a reminder for Done, In 30 minutes, or Not tonight.")
        }
    }

    private var dataSection: some View {
        Section {
            Button("Export a backup") { exportURL = Backup(model: model).write() }
            if let exportURL {
                ShareLink(item: exportURL) { Label("Share backup file", systemImage: "square.and.arrow.up") }
            }
            Button("Restore from a backup…") { importing = true }
            Button("Erase all data", role: .destructive) { confirmReset = true }
        } header: {
            Text("Your data")
        } footer: {
            Text(SharedStore.isShared ? "Saved on this iPhone and in its iCloud backup. The backup file includes your photos." : "Saved on this iPhone and in its iCloud backup. The backup file includes your photos. (The widget needs the App Group capability to see your data.)")
        }
    }
}

/// One JSON file with the state and every photo.
struct Backup: Codable {
    var format = "barrier-backup"
    var version = 1
    var exportedAt = Date()
    var state: AppState
    var photos: [String: Data]

    @MainActor
    init(model: AppModel) {
        state = model.state
        var p: [String: Data] = [:]
        for m in model.state.photos { if let d = model.photos.data(m.id) { p[m.id] = d } }
        photos = p
    }

    static func decode(_ data: Data) throws -> Backup {
        let b = try StateCoder.decoder().decode(Backup.self, from: data)
        guard b.format == "barrier-backup" else { throw CocoaError(.fileReadCorruptFile) }
        return b
    }

    func write() -> URL? {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("Barrier backup \(Day.routineDay().iso).json")
        guard let data = try? StateCoder.encoder().encode(self) else { return nil }
        do {
            try data.write(to: url, options: .atomic)
            return url
        } catch {
            return nil
        }
    }

    @MainActor
    func restore(into model: AppModel) {
        model.photos.deleteAll()
        for (id, data) in photos {
            if let img = UIImage(data: data) { try? model.photos.save(img, id: id) }
        }
        var s = state
        s.onboarded = true
        model.update { $0 = s }
        model.saveNow()
        model.show("Backup restored.")
    }
}
