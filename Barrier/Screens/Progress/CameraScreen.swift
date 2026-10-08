import AVFoundation
import BarrierCore
import PhotosUI
import SwiftUI

/// Front camera with a faint "ghost" of your last photo, so every photo lines
/// up with the one before. Photos stay on the phone.
struct CameraScreen: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var camera = CameraController()
    @State private var captured: UIImage?
    @State private var ghostOpacity: Double = 0.35
    @State private var pickerItem: PhotosPickerItem?
    @State private var saving = false

    private var lastPhoto: UIImage? {
        guard let last = model.state.photos.max(by: { $0.at < $1.at }) else { return nil }
        return model.photos.image(last.id)
    }

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
                        Ellipse()
                            .strokeBorder(.white.opacity(0.55), style: StrokeStyle(lineWidth: 2, dash: [7, 6]))
                            .frame(width: 240, height: 320)
                            .allowsHitTesting(false)
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
        .task { await camera.start() }
        .onDisappear { camera.stop() }
        .onChange(of: pickerItem) { _, item in
            guard let item else { return }
            Task {
                if let data = try? await item.loadTransferable(type: Data.self), let img = UIImage(data: data) {
                    captured = img.normalized()
                }
                pickerItem = nil
            }
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
            if captured == nil && camera.state == .running {
                Text(lastPhoto == nil ? "Window light, no makeup, face the camera." : "Line up with last time. Same spot, same light.")
                    .font(.footnote.weight(.medium))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(.black.opacity(0.35), in: RoundedRectangle(cornerRadius: 10))
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
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
                Button {
                    camera.capture { img in captured = img }
                    Haptics.tap(model.state.settings.haptics)
                } label: {
                    Circle().strokeBorder(.white, lineWidth: 4).frame(width: 76, height: 76)
                        .overlay(Circle().fill(.white.opacity(0.18)).padding(8))
                }
                .disabled(camera.state != .running)
                .accessibilityLabel("Take photo")
                Spacer()
                Color.clear.frame(width: 56, height: 56)
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 18)
        .background(Color.black)
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
        let meta = PhotoMeta(day: model.today)
        Task {
            do {
                try model.photos.save(img, id: meta.id)
                model.update { $0.photos.append(meta) }
                model.show(model.state.photos.count == 1 ? "Your “before” is saved." : "Photo saved.")
                dismiss()
            } catch {
                model.show("Couldn’t save the photo.")
                saving = false
            }
        }
    }
}

@Observable
final class CameraController: NSObject, AVCapturePhotoCaptureDelegate {
    enum State { case starting, running, denied, unavailable }

    var state: State = .starting
    @ObservationIgnored let session = AVCaptureSession()
    @ObservationIgnored private let output = AVCapturePhotoOutput()
    @ObservationIgnored private let queue = DispatchQueue(label: "barrier.camera")
    @ObservationIgnored private var completion: ((UIImage) -> Void)?
    @ObservationIgnored private var configured = false

    func start() async {
        var granted = AVCaptureDevice.authorizationStatus(for: .video) == .authorized
        if AVCaptureDevice.authorizationStatus(for: .video) == .notDetermined {
            granted = await AVCaptureDevice.requestAccess(for: .video)
        }
        guard granted else {
            await MainActor.run { state = AVCaptureDevice.authorizationStatus(for: .video) == .denied || AVCaptureDevice.authorizationStatus(for: .video) == .restricted ? .denied : .unavailable }
            return
        }
        let ok: Bool = await withCheckedContinuation { cont in
            queue.async {
                if !self.configured {
                    self.configured = self.configure()
                }
                if self.configured && !self.session.isRunning { self.session.startRunning() }
                cont.resume(returning: self.configured)
            }
        }
        await MainActor.run { state = ok ? .running : .unavailable }
    }

    func stop() {
        queue.async { if self.session.isRunning { self.session.stopRunning() } }
    }

    private func configure() -> Bool {
        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front),
              let input = try? AVCaptureDeviceInput(device: device) else { return false }
        session.beginConfiguration()
        session.sessionPreset = .photo
        guard session.canAddInput(input), session.canAddOutput(output) else {
            session.commitConfiguration()
            return false
        }
        session.addInput(input)
        session.addOutput(output)
        session.commitConfiguration()
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
        // Save what the preview showed (mirrored), so the ghost lines up next time.
        let upright = img.normalized()
        let mirrored = upright.withHorizontallyFlippedOrientation().normalized()
        DispatchQueue.main.async { self.completion?(mirrored) }
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
