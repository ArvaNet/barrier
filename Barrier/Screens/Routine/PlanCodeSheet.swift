import AVFoundation
import BarrierCore
import SwiftUI

/// A routine from the clinic's sheet: scan the code, check it against the paper, then use it.
/// Nothing changes until the patient has seen every step in words.
struct PlanCodeSheet: View {
    @Environment(\.dismiss) private var dismiss
    var request: PlanCodeRequest
    @State private var scanned: PlanCode?

    var body: some View {
        NavigationStack {
            Group {
                switch request.start {
                case .scan:
                    PlanCodeScanner { scanned = $0 }
                        .navigationDestination(item: $scanned) { code in
                            PlanCodeReview(code: code) { dismiss() }
                        }
                case .review(let code):
                    PlanCodeReview(code: code) { dismiss() }
                case .problem(let error):
                    PlanCodeProblem(error: error)
                        .navigationTitle("Routine from your clinic")
                        .navigationBarTitleDisplayMode(.inline)
                }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            }
        }
    }
}

// MARK: - Check it against the sheet

struct PlanCodeReview: View {
    @Environment(AppModel.self) private var model
    var code: PlanCode
    var done: () -> Void

    var body: some View {
        let sum = code.summary(for: model.state, today: model.today)
        ScrollViewReader { proxy in
        List {
            Group {
                ForEach(sum.sections) { section in
                    Section {
                        if let rotation = section.rotation {
                            Label(rotation, systemImage: "arrow.triangle.2.circlepath")
                                .font(.subheadline)
                                .foregroundStyle(Palette.ink2)
                        }
                        ForEach(section.rows) { row in
                            PlanCodeRow(row: row)
                        }
                    } header: {
                        Text("\(section.title), in this order")
                    } footer: {
                        if let note = footer(section) { Text(note) }
                    }
                    .id(section.id)
                }
                if let text = sum.ifIrritated {
                    Section("If your skin gets irritated") {
                        Text(text).font(.subheadline).foregroundStyle(Palette.ink)
                    }
                    .id("if-irritated")
                }
            }
            .rows()
        }
        .barrierList()
        .listSectionSpacing(.compact)
        .contentMargins(.top, 4, for: .scrollContent)
        // At the end, the last section clears the fade above the button.
        .contentMargins(.bottom, 28, for: .scrollContent)
        // The title stays on the 16 pt line above the list (inside a row, its edge gets clipped).
        .safeAreaInset(edge: .top, spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                if let clinic = sum.clinic { Kicker("From \(clinic)") }
                Text("Check it against your sheet")
                    .font(.barrierH2).tracking(-0.4)
                    .foregroundStyle(Palette.ink)
                Text("This is what the code says. If anything differs from the sheet your clinic gave you, follow the sheet.")
                    .font(.subheadline)
                    .foregroundStyle(Palette.ink2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, Metrics.margin)
            .padding(.top, 8)
            .padding(.bottom, 4)
            .background(Palette.bg)
        }
        .onAppear {
            // Screenshot hook: `-screen plan-code-bottom`.
            guard model.launch.screen == "plan-code-bottom", let end = sum.ifIrritated != nil ? "if-irritated" : sum.sections.last?.id else { return }
            // To the top: the list stops at its very end, margin included.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { proxy.scrollTo(end, anchor: .top) }
        }
        }
        .navigationTitle("Routine from your clinic")
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            VStack(spacing: 8) {
                Button(sum.sections.count == 1 ? "Use this routine" : "Use these routines") {
                    model.load(code)
                    done()
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(model.loadFailed)
                Text(model.state.onboarded ? "Your history, photos and reminder times stay." : "You can change any step afterwards.")
                    .font(.footnote)
                    .foregroundStyle(Palette.ink3)
            }
            .padding(.horizontal, Metrics.margin)
            .padding(.top, 12)
            .padding(.bottom, 8)
            // Rows fade out above the button instead of stopping at a hard line.
            .background(alignment: .top) {
                VStack(spacing: 0) {
                    LinearGradient(colors: [Palette.bg.opacity(0), Palette.bg], startPoint: .top, endPoint: .bottom)
                        .frame(height: 28)
                    Palette.bg
                }
                .padding(.top, -28)
                .ignoresSafeArea()
                .allowsHitTesting(false)
            }
        }
    }

    /// "Replaces your evening routine. Starts tomorrow: tonight is already logged."
    private func footer(_ section: PlanCodeSummary.Section) -> String? {
        var parts: [String] = []
        if section.replaces {
            parts.append("Replaces your \(section.slot.isBody ? section.title : section.title.lowercased()) routine.")
        }
        if section.starts > model.today {
            parts.append("Starts tomorrow: \(section.slot == .pm ? "tonight" : "today") is already logged.")
        }
        return parts.isEmpty ? nil : parts.joined(separator: " ")
    }
}

/// One step as the sheet would say it: the product, how often, how much, then the prescriber's own words.
private struct PlanCodeRow: View {
    var row: PlanCodeSummary.Row

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            // Treatment steps carry their hue, as in the routine editor.
            Group {
                if let hue = row.kind.hue { HueDot(hue: hue, size: 10) } else { Color.clear }
            }
            .frame(width: 10, height: 10)
            .padding(.top, 6)
            VStack(alignment: .leading, spacing: 3) {
                Text(row.name).font(.body.weight(.medium)).foregroundStyle(Palette.ink)
                ForEach(row.lines, id: \.self) { line in
                    Text(line).font(.subheadline).foregroundStyle(Palette.ink2)
                }
                if let note = row.note {
                    Text("“\(note)”").font(.footnote).foregroundStyle(Palette.ink3).padding(.top, 1)
                }
            }
            .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 2)
        .alignmentGuide(.listRowSeparatorLeading) { _ in 0 }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - A code that can't be used

extension PlanCodeError {
    var title: String {
        switch self {
        case .notACode: return "That’s not a routine code"
        case .unreadable: return "The code didn’t read fully"
        case .newer: return "This code needs a newer Tendwell"
        case .invalid: return "This code has a mistake in it"
        }
    }

    var advice: String {
        switch self {
        case .notACode: return "Tendwell reads the code printed on the sheet from your clinic."
        case .unreadable: return "Try again in good light, with the whole code inside the frame."
        case .newer: return "Update the app, then scan it again. Nothing was changed."
        case .invalid: return "Nothing was changed. Ask your clinic for a new code, or enter the routine by hand from your sheet."
        }
    }
}

struct PlanCodeProblem: View {
    var error: PlanCodeError

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Image(systemName: "qrcode")
                .font(.system(size: 34))
                .foregroundStyle(Palette.ink2)
                .padding(.bottom, 8)
                .accessibilityHidden(true)
            Text(error.title).font(.barrierH2).tracking(-0.4).foregroundStyle(Palette.ink)
            Text(error.advice).font(.body).foregroundStyle(Palette.ink2).fixedSize(horizontal: false, vertical: true)
            Spacer()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, Metrics.margin)
        .padding(.top, 32)
        .background(Palette.bg.ignoresSafeArea())
    }
}

// MARK: - Scanner

struct PlanCodeScanner: View {
    @Environment(AppModel.self) private var model
    var onCode: (PlanCode) -> Void
    @State private var scanner = CodeScanner()
    @State private var problem: PlanCodeError?

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if scanner.state == .running {
                CameraPreview(session: scanner.session).ignoresSafeArea()
                RoundedRectangle(cornerRadius: Metrics.stageRadius, style: .continuous)
                    .strokeBorder(.white.opacity(0.7), style: StrokeStyle(lineWidth: 2, dash: [7, 6]))
                    .frame(width: 250, height: 250)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            } else {
                unavailable
            }
        }
        .foregroundStyle(.white)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if scanner.state == .running { hint }
        }
        .navigationTitle("Scan your clinic’s code")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .toolbarBackground(Color.black, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .onAppear {
            // Also on the way back from the check screen.
            scanner.onText = { read($0) }
            Task { await scanner.start() }
        }
        .onDisappear { scanner.stop() }
    }

    private var hint: some View {
        VStack(spacing: 4) {
            Text(problem?.title ?? "Hold the whole code inside the frame")
                .font(.subheadline.weight(.semibold))
            Text(problem?.advice ?? "It’s the square code on the sheet from your clinic.")
                .font(.footnote)
                .opacity(0.8)
        }
        .multilineTextAlignment(.center)
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 24)
        .padding(.vertical, 18)
        .background(Color.black)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var unavailable: some View {
        VStack(spacing: 14) {
            Image(systemName: scanner.state == .denied ? "lock" : "camera").font(.largeTitle)
            Text(scanner.state == .denied ? "Camera access is off" : scanner.state == .starting ? "Starting camera…" : "No camera here")
                .font(.headline)
            if scanner.state == .denied {
                Button("Open Settings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                }
                .buttonStyle(SecondaryButtonStyle(compact: true))
            }
            if scanner.state != .starting {
                Text("You can also enter the routine by hand from your sheet.").font(.footnote).opacity(0.7)
            }
        }
        .multilineTextAlignment(.center)
        .padding()
    }

    private func read(_ text: String) {
        do {
            let code = try PlanCode(link: text)
            problem = nil
            Haptics.success(model.state.settings.haptics)
            onCode(code)
        } catch {
            let found = error as? PlanCodeError ?? .unreadable
            if problem != found { Haptics.soft(model.state.settings.haptics) }
            withAnimation(Motion.ui) { problem = found }
        }
    }
}

/// The rear camera, reading QR codes only. Each code is reported once while it stays in view.
@Observable
final class CodeScanner: NSObject, AVCaptureMetadataOutputObjectsDelegate, @unchecked Sendable {
    enum Phase { case starting, running, denied, unavailable }

    var state: Phase = .starting
    @ObservationIgnored let session = AVCaptureSession()
    @ObservationIgnored var onText: ((String) -> Void)?
    @ObservationIgnored private let output = AVCaptureMetadataOutput()
    @ObservationIgnored private let queue = DispatchQueue(label: "barrier.scanner")
    @ObservationIgnored private var last: (text: String, at: Date)?

    func start() async {
        var granted = AVCaptureDevice.authorizationStatus(for: .video) == .authorized
        if AVCaptureDevice.authorizationStatus(for: .video) == .notDetermined {
            granted = await AVCaptureDevice.requestAccess(for: .video)
        }
        guard granted else {
            let status = AVCaptureDevice.authorizationStatus(for: .video)
            await MainActor.run { state = status == .denied || status == .restricted ? .denied : .unavailable }
            return
        }
        let ok: Bool = await withCheckedContinuation { cont in
            queue.async {
                let ok = self.configure()
                if ok && !self.session.isRunning { self.session.startRunning() }
                cont.resume(returning: ok)
            }
        }
        await MainActor.run {
            last = nil
            state = ok ? .running : .unavailable
        }
    }

    func stop() {
        queue.async { if self.session.isRunning { self.session.stopRunning() } }
    }

    private func configure() -> Bool {
        if !session.inputs.isEmpty { return true }
        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
              let input = try? AVCaptureDeviceInput(device: device) else { return false }
        session.beginConfiguration()
        defer { session.commitConfiguration() }
        guard session.canAddInput(input), session.canAddOutput(output) else { return false }
        session.addInput(input)
        session.addOutput(output)
        guard output.availableMetadataObjectTypes.contains(.qr) else {
            session.removeInput(input)
            session.removeOutput(output)
            return false
        }
        output.metadataObjectTypes = [.qr]
        output.setMetadataObjectsDelegate(self, queue: .main)
        return true
    }

    func metadataOutput(_ output: AVCaptureMetadataOutput, didOutput metadataObjects: [AVMetadataObject], from connection: AVCaptureConnection) {
        guard let text = metadataObjects.compactMap({ ($0 as? AVMetadataMachineReadableCodeObject)?.stringValue }).first else { return }
        let now = Date()
        // The camera reports the same code many times a second.
        if let last, last.text == text, now.timeIntervalSince(last.at) < 2.5 {
            self.last = (text, now)
            return
        }
        last = (text, now)
        onText?(text)
    }
}
