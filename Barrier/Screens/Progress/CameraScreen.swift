import AVFoundation
import BarrierCore
import PhotosUI
import SwiftUI

/// Progress photos with a faint "ghost" of the last one, so every photo lines
/// up with the one before. Face: front camera. Back: rear camera with a
/// 5-second self-timer. Photos stay on the phone.
struct CameraScreen: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var area: Area

    /// Opened for a body photo (e.g. a back procedure) without a body routine: still offer the choice.
    private let openedForBody: Bool

    init(initialArea: Area = .face) {
        _area = State(initialValue: initialArea)
        openedForBody = initialArea == .body
    }
    @State private var camera = CameraController()
    @State private var captured: UIImage?
    /// When an imported photo was taken; nil for a photo taken here, now.
    @State private var capturedAt: Date?
    @State private var ghostOpacity: Double = 0.35
    @State private var pickerItem: PhotosPickerItem?
    @State private var saving = false
    @State private var countdown: Int?
    @State private var timerTask: Task<Void, Never>?
    /// The previous photo of this area, decoded once (the overlay redraws on every slider move).
    @State private var lastPhoto: UIImage?
    @State private var started = false

    private var hasBody: Bool { model.hasBodyRoutine }
    private var bodyName: String { model.bodyAreaName }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            VStack(spacing: 0) {
                ZStack {
                    if let captured {
                        Image(uiImage: captured).resizable().scaledToFill()
                    } else if camera.state == .running {
                        CameraPreview(session: camera.session)
                        if let ghost = lastPhoto, ghostOpacity > 0 {
                            Image(uiImage: ghost).resizable().scaledToFill().opacity(ghostOpacity).allowsHitTesting(false)
                        }
                        guide.allowsHitTesting(false)
                        if let countdown {
                            Text("\(countdown)")
                                .font(Typeface.display(120, weight: 380))
                                .shadow(color: .black.opacity(0.5), radius: 12)
                                .contentTransition(.numericText(countsDown: true))
                                .accessibilityLabel("\(countdown) seconds")
                        }
                    } else {
                        unavailable
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipped()
                .overlay(alignment: .top) { topBar }
                bottomBar
            }
        }
        .foregroundStyle(.white)
        .statusBarHidden()
        .task {
            guard !started else { return }
            started = true
            loadGhost()
            await camera.start(position: position(for: area))
        }
        .onChange(of: area) { _, new in
            cancelTimer()
            captured = nil
            loadGhost()
            // With access denied, keep the "Open Settings" message rather than "No camera here".
            if camera.state == .running { Task { await camera.switchTo(position(for: new)) } }
        }
        .onDisappear {
            cancelTimer()
            camera.stop()
        }
        .onChange(of: pickerItem) { _, item in
            guard let item else { return }
            Task {
                if let data = try? await item.loadTransferable(type: Data.self), let img = UIImage(data: data) {
                    captured = img.normalized()
                    capturedAt = PhotoDate.taken(data)
                }
                pickerItem = nil
            }
        }
    }

    private func position(for area: Area) -> AVCaptureDevice.Position { area == .face ? .front : .back }

    private func loadGhost() {
        let last = model.state.photos.filter { $0.place == area }.max { $0.at < $1.at }
        lastPhoto = last.flatMap { model.photos.image($0.id)?.resized(maxSide: 1200) }
    }

    @ViewBuilder
    private var guide: some View {
        if area == .face {
            Ellipse()
                .strokeBorder(.white.opacity(0.55), style: StrokeStyle(lineWidth: 2, dash: [7, 6]))
                .frame(width: 240, height: 320)
        } else {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .strokeBorder(.white.opacity(0.55), style: StrokeStyle(lineWidth: 2, dash: [7, 6]))
                .frame(width: 270, height: 380)
        }
    }

    private var topBar: some View {
        VStack(spacing: 10) {
            HStack {
                Button { dismiss() } label: {
                    Image(systemName: "xmark").font(.system(size: 17, weight: .semibold)).frame(width: 44, height: 44)
                        .background(.black.opacity(0.35), in: Circle())
                }
                .accessibilityLabel("Close camera")
                Spacer()
                if captured == nil, lastPhoto != nil, camera.state == .running {
                    HStack(spacing: 8) {
                        Image(systemName: "square.on.square.dashed").font(.footnote)
                        Slider(value: $ghostOpacity, in: 0...0.6).frame(width: 110).tint(.white)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(.black.opacity(0.35), in: RoundedRectangle(cornerRadius: 12))
                    .accessibilityLabel("Last photo overlay")
                }
            }
            if (hasBody || openedForBody) && captured == nil {
                Picker("Area", selection: $area) {
                    Text("Face").tag(Area.face)
                    Text(bodyName).tag(Area.body)
                }
                .pickerStyle(.segmented)
                .frame(width: 220)
                .colorScheme(.dark)
            }
            if captured == nil && camera.state == .running {
                Text(hint)
                    .font(.footnote.weight(.medium))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(.black.opacity(0.35), in: RoundedRectangle(cornerRadius: 10))
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }

    private var hint: String {
        if area == .body {
            return lastPhoto == nil ? "Rear camera, 5-second timer. \(Guidance.backPhotoTips)" : "Line up with last time. Same spot, same distance, same light."
        }
        return lastPhoto == nil ? "Window light, no makeup, face the camera." : "Line up with last time. Same spot, same light."
    }

    private var bottomBar: some View {
        HStack {
            if captured != nil {
                Button("Retake") { captured = nil }
                    .font(.body.weight(.semibold))
                    .frame(width: 90, height: 50)
                Spacer()
                Button {
                    save()
                } label: {
                    Text(saving ? "Saving…" : "Save photo").frame(width: 160)
                }
                .buttonStyle(PrimaryButtonStyle(fill: Palette.stageAccent))
                .frame(width: 170)
                .disabled(saving)
            } else {
                PhotosPicker(selection: $pickerItem, matching: .images) {
                    Image(systemName: "photo.on.rectangle").font(.title3).frame(width: 56, height: 56)
                }
                .accessibilityLabel("Import from Photos")
                Spacer()
                Button(action: shutter) {
                    ZStack {
                        Circle().strokeBorder(.white, lineWidth: 4).frame(width: 76, height: 76)
                        if countdown != nil {
                            RoundedRectangle(cornerRadius: 6).fill(.white).frame(width: 24, height: 24)
                        } else {
                            Circle().fill(.white.opacity(0.18)).padding(8).frame(width: 76, height: 76)
                            if area == .body {
                                Image(systemName: "timer").font(.system(size: 20, weight: .semibold))
                            }
                        }
                    }
                }
                .disabled(camera.state != .running)
                .accessibilityLabel(countdown != nil ? "Cancel timer" : (area == .body ? "Take photo in 5 seconds" : "Take photo"))
                Spacer()
                Color.clear.frame(width: 56, height: 56)
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 18)
        .background(Color.black)
    }

    private func shutter() {
        if countdown != nil {
            cancelTimer()
            return
        }
        guard area == .body else {
            camera.capture { img in
                captured = img
                capturedAt = nil
            }
            Haptics.tap(model.state.settings.haptics)
            return
        }
        // Back photos: a 5-second self-timer so you can hold the phone behind you
        // or prop it up.
        timerTask = Task { @MainActor in
            for n in stride(from: 5, through: 1, by: -1) {
                withAnimation { countdown = n }
                Haptics.tap(model.state.settings.haptics)
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                if Task.isCancelled { return }
            }
            countdown = nil
            camera.capture { img in
                captured = img
                capturedAt = nil
            }
            Haptics.success(model.state.settings.haptics)
        }
    }

    private func cancelTimer() {
        timerTask?.cancel()
        timerTask = nil
        countdown = nil
    }

    @ViewBuilder
    private var unavailable: some View {
        VStack(spacing: 14) {
            Image(systemName: camera.state == .denied ? "lock" : "camera").font(.largeTitle)
            Text(camera.state == .denied ? "Camera access is off" : camera.state == .starting ? "Starting camera…" : "No camera here")
                .font(.headline)
            if camera.state == .denied {
                Button("Open Settings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                }
                .buttonStyle(SecondaryButtonStyle(compact: true))
            }
            Text("You can also import a photo.").font(.footnote).opacity(0.7)
        }
        .padding()
    }

    private func save() {
        guard let img = captured else { return }
        saving = true
        // An imported photo keeps the day it was taken, so it pairs with procedures correctly.
        let day = capturedAt.map { Day.routineDay($0) } ?? model.today
        let meta = PhotoMeta(day: day, at: capturedAt ?? Date(), area: area)
        let firstOfArea = !model.state.photos.contains { $0.place == area }
        Task {
            do {
                try model.photos.save(img, id: meta.id)
                model.update { $0.photos.append(meta) }
                model.show(firstOfArea ? "Your “before” is saved." : day == model.today ? "Photo saved." : "Photo saved, dated \(day.short).")
                dismiss()
            } catch {
                model.show("Couldn’t save the photo.")
                saving = false
            }
        }
    }
}

@Observable
final class CameraController: NSObject, AVCapturePhotoCaptureDelegate, @unchecked Sendable {
    enum Phase { case starting, running, denied, unavailable }

    var state: Phase = .starting
    @ObservationIgnored let session = AVCaptureSession()
    @ObservationIgnored private let output = AVCapturePhotoOutput()
    @ObservationIgnored private let queue = DispatchQueue(label: "barrier.camera")
    @ObservationIgnored private var completion: ((UIImage) -> Void)?
    @ObservationIgnored private var position: AVCaptureDevice.Position = .front

    func start(position: AVCaptureDevice.Position) async {
        var granted = AVCaptureDevice.authorizationStatus(for: .video) == .authorized
        if AVCaptureDevice.authorizationStatus(for: .video) == .notDetermined {
            granted = await AVCaptureDevice.requestAccess(for: .video)
        }
        guard granted else {
            let status = AVCaptureDevice.authorizationStatus(for: .video)
            await MainActor.run { state = status == .denied || status == .restricted ? .denied : .unavailable }
            return
        }
        await switchTo(position)
    }

    /// Use the front or rear camera (also the first start).
    func switchTo(_ position: AVCaptureDevice.Position) async {
        let ok: Bool = await withCheckedContinuation { cont in
            queue.async {
                let ok = self.configure(position)
                if ok && !self.session.isRunning { self.session.startRunning() }
                cont.resume(returning: ok)
            }
        }
        await MainActor.run { state = ok ? .running : .unavailable }
    }

    func stop() {
        queue.async { if self.session.isRunning { self.session.stopRunning() } }
    }

    private func configure(_ position: AVCaptureDevice.Position) -> Bool {
        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: position),
              let input = try? AVCaptureDeviceInput(device: device) else { return false }
        session.beginConfiguration()
        defer { session.commitConfiguration() }
        session.sessionPreset = .photo
        for old in session.inputs { session.removeInput(old) }
        guard session.canAddInput(input) else { return false }
        session.addInput(input)
        if !session.outputs.contains(output) {
            guard session.canAddOutput(output) else { return false }
            session.addOutput(output)
        }
        self.position = position
        return true
    }

    func capture(_ done: @escaping (UIImage) -> Void) {
        completion = done
        let settings = AVCapturePhotoSettings()
        if let conn = output.connection(with: .video) {
            if conn.isVideoRotationAngleSupported(90) { conn.videoRotationAngle = 90 }
        }
        output.capturePhoto(with: settings, delegate: self)
    }

    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        guard let data = photo.fileDataRepresentation(), let img = UIImage(data: data) else { return }
        let upright = img.normalized()
        // The front preview is mirrored; save what it showed so the ghost lines up.
        let result = position == .front ? upright.withHorizontallyFlippedOrientation().normalized() : upright
        DispatchQueue.main.async { self.completion?(result) }
    }
}

struct CameraPreview: UIViewRepresentable {
    let session: AVCaptureSession

    func makeUIView(context: Context) -> PreviewView {
        let v = PreviewView()
        v.previewLayer.session = session
        v.previewLayer.videoGravity = .resizeAspectFill
        return v
    }

    func updateUIView(_ uiView: PreviewView, context: Context) {}

    final class PreviewView: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
    }
}
