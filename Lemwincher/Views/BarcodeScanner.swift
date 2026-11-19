import SwiftUI
import UIKit
import AVFoundation

/// Feuille plein écran : scanner de code-barres + saisie manuelle.
struct BarcodeScannerSheet: View {
    let onCode: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var access: Bool? = nil
    @State private var manualCode = ""

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()
                switch access {
                case .some(true):
                    ScannerRepresentable(onCode: onCode)
                        .ignoresSafeArea()
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(Color.white.opacity(0.9), lineWidth: 3)
                        .frame(width: 280, height: 160)
                        .allowsHitTesting(false)
                case .some(false):
                    VStack(spacing: 12) {
                        Image(systemName: "camera.fill").font(.largeTitle)
                        Text("Accès à la caméra refusé").font(.headline)
                        Text("Autorisez la caméra pour Lemwincher dans les Réglages de l'iPhone, ou tapez le code-barres ci-dessous.")
                            .multilineTextAlignment(.center)
                        Button("Ouvrir les Réglages") {
                            if let url = URL(string: UIApplication.openSettingsURLString) {
                                UIApplication.shared.open(url)
                            }
                        }
                        .buttonStyle(.glassProminent)
                    }
                    .foregroundStyle(Color.white)
                    .padding(32)
                case .none:
                    ProgressView().tint(Color.white)
                }
            }
            .safeAreaInset(edge: .bottom) {
                HStack {
                    TextField("Ou tapez le code-barres", text: $manualCode)
                        .keyboardType(.numberPad)
                        .textFieldStyle(.roundedBorder)
                    Button("OK") {
                        let code = manualCode.trimmed
                        if !code.isEmpty { onCode(code) }
                    }
                    .buttonStyle(.glassProminent)
                    .disabled(manualCode.trimmed.isEmpty)
                }
                .padding()
                .background(.ultraThinMaterial)
            }
            .navigationTitle("Scanner un produit")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Fermer") { dismiss() }
                }
            }
        }
        .task {
            switch AVCaptureDevice.authorizationStatus(for: .video) {
            case .authorized:
                access = true
            case .notDetermined:
                access = await AVCaptureDevice.requestAccess(for: .video)
            default:
                access = false
            }
        }
    }
}

struct ScannerRepresentable: UIViewControllerRepresentable {
    let onCode: (String) -> Void

    func makeUIViewController(context: Context) -> ScannerViewController {
        let controller = ScannerViewController()
        controller.onCode = onCode
        return controller
    }

    func updateUIViewController(_ controller: ScannerViewController, context: Context) {
        controller.onCode = onCode
    }
}

/// Lecture des codes EAN/UPC avec la caméra arrière.
final class ScannerViewController: UIViewController, AVCaptureMetadataOutputObjectsDelegate {
    var onCode: ((String) -> Void)?

    private let session = AVCaptureSession()
    private var previewLayer: AVCaptureVideoPreviewLayer?
    private var hasFoundCode = false

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black

        guard let device = AVCaptureDevice.default(for: .video),
              let input = try? AVCaptureDeviceInput(device: device),
              session.canAddInput(input) else {
            showMessage("Caméra indisponible sur cet appareil.")
            return
        }
        session.addInput(input)

        let output = AVCaptureMetadataOutput()
        guard session.canAddOutput(output) else {
            showMessage("Lecture des codes-barres indisponible.")
            return
        }
        session.addOutput(output)
        output.setMetadataObjectsDelegate(self, queue: DispatchQueue.main)
        let wanted: [AVMetadataObject.ObjectType] = [.ean13, .ean8, .upce, .code128]
        output.metadataObjectTypes = wanted.filter { output.availableMetadataObjectTypes.contains($0) }

        let layer = AVCaptureVideoPreviewLayer(session: session)
        layer.videoGravity = .resizeAspectFill
        view.layer.addSublayer(layer)
        previewLayer = layer
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        previewLayer?.frame = view.bounds
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        hasFoundCode = false
        let session = self.session
        DispatchQueue.global(qos: .userInitiated).async {
            if !session.isRunning { session.startRunning() }
        }
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        let session = self.session
        DispatchQueue.global(qos: .userInitiated).async {
            if session.isRunning { session.stopRunning() }
        }
    }

    func metadataOutput(_ output: AVCaptureMetadataOutput,
                        didOutput metadataObjects: [AVMetadataObject],
                        from connection: AVCaptureConnection) {
        guard !hasFoundCode,
              let object = metadataObjects.first as? AVMetadataMachineReadableCodeObject,
              let code = object.stringValue, !code.isEmpty else { return }
        hasFoundCode = true
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        onCode?(code)
    }

    private func showMessage(_ text: String) {
        let label = UILabel()
        label.text = text
        label.textColor = .white
        label.textAlignment = .center
        label.numberOfLines = 0
        label.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(label)
        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            label.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            label.leadingAnchor.constraint(greaterThanOrEqualTo: view.leadingAnchor, constant: 24),
            label.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -24),
        ])
    }
}
