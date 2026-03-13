import SwiftUI
import CoreImage.CIFilterBuiltins

struct RemoteControlSettingsView: View {
    @ObservedObject private var server = RemoteServerManager.shared
    @State private var port: String = ""
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Remote Control")
                    .font(.headline)
                Spacer()
                Button("Done") { dismiss() }
                    .buttonStyle(.borderedProminent)
            }
            .padding()

            Divider()

            ScrollView {
                VStack(spacing: 20) {
                    // Enable/Disable
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Enable Remote Control")
                                .font(.body)
                            Text("Allow devices on your network to control playback")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                        Toggle("", isOn: Binding(
                            get: { server.isEnabled },
                            set: { server.isEnabled = $0 }
                        ))
                        .toggleStyle(.switch)
                    }
                    .padding()
                    .background(Color(nsColor: .controlBackgroundColor))
                    .cornerRadius(8)

                    // Port
                    HStack {
                        Text("Port")
                        Spacer()
                        TextField("8080", text: $port)
                            .frame(width: 80)
                            .textFieldStyle(.roundedBorder)
                            .multilineTextAlignment(.center)
                            .onSubmit {
                                if let p = UInt16(port), p > 1024 {
                                    server.port = p
                                    if server.isEnabled { server.start() }
                                }
                            }
                    }
                    .padding()
                    .background(Color(nsColor: .controlBackgroundColor))
                    .cornerRadius(8)

                    // Status & QR Code
                    if server.isRunning, let url = server.serverURL {
                        VStack(spacing: 16) {
                            HStack(spacing: 8) {
                                Circle()
                                    .fill(.green)
                                    .frame(width: 8, height: 8)
                                Text("Server running")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                            }

                            Text(url)
                                .font(.system(.body, design: .monospaced))
                                .textSelection(.enabled)

                            Text("Scan with your phone to connect")
                                .font(.caption)
                                .foregroundColor(.secondary)

                            if let qrImage = generateQRCode(from: url) {
                                Image(nsImage: qrImage)
                                    .interpolation(.none)
                                    .resizable()
                                    .scaledToFit()
                                    .frame(width: 180, height: 180)
                                    .background(Color.white)
                                    .cornerRadius(8)
                            }
                        }
                        .padding()
                        .frame(maxWidth: .infinity)
                        .background(Color(nsColor: .controlBackgroundColor))
                        .cornerRadius(8)
                    } else if server.isEnabled {
                        HStack(spacing: 8) {
                            ProgressView()
                                .controlSize(.small)
                            Text("Starting server...")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                        .padding()
                        .frame(maxWidth: .infinity)
                        .background(Color(nsColor: .controlBackgroundColor))
                        .cornerRadius(8)
                    }
                }
                .padding()
            }
        }
        .frame(width: 420, height: 480)
        .onAppear {
            port = "\(server.port)"
        }
    }

    private func generateQRCode(from string: String) -> NSImage? {
        let context = CIContext()
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(string.utf8)
        filter.correctionLevel = "M"

        guard let ciImage = filter.outputImage else { return nil }

        let scale = 10.0
        let scaled = ciImage.transformed(by: CGAffineTransform(scaleX: scale, y: scale))

        guard let cgImage = context.createCGImage(scaled, from: scaled.extent) else { return nil }
        return NSImage(cgImage: cgImage, size: NSSize(width: scaled.extent.width, height: scaled.extent.height))
    }
}
