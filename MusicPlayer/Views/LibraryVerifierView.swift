import SwiftUI

struct LibraryVerifierView: View {
    @StateObject private var verifier = LibraryVerifier()
    @Environment(\.dismiss) var dismiss

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Verify Library")
                    .font(.headline)
                Spacer()
                Button("Close") { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }
            .padding()

            Divider()

            if verifier.isVerifying {
                // Progress
                VStack(spacing: 12) {
                    ProgressView(value: verifier.progress)
                    Text("Checking \(verifier.totalChecked) tracks...")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if !verifier.results.isEmpty {
                        Text("\(verifier.results.count) issues found so far")
                            .font(.caption)
                            .foregroundColor(.orange)
                    }
                }
                .padding()
            } else if verifier.results.isEmpty && verifier.totalChecked > 0 {
                // All clean
                VStack(spacing: 12) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 48))
                        .foregroundColor(.green)
                    Text("Library is healthy!")
                        .font(.title3)
                        .fontWeight(.medium)
                    Text("All \(verifier.totalChecked) tracks verified successfully")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if !verifier.results.isEmpty {
                // Results
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("\(verifier.results.count) issues found")
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .foregroundColor(.orange)
                        Spacer()
                        Button("Remove All Damaged") {
                            verifier.removeAllDamaged()
                        }
                        .buttonStyle(.bordered)
                        .foregroundColor(.red)
                    }
                    .padding(.horizontal)
                    .padding(.top, 8)

                    List(verifier.results) { result in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(result.trackTitle)
                                    .font(.subheadline)
                                    .lineLimit(1)
                                Text(result.filePath)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                            Spacer()
                            Text(result.errorType.rawValue)
                                .font(.caption)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.red.opacity(0.12))
                                .cornerRadius(4)
                                .foregroundColor(.red)

                            Button(action: { verifier.removeTrack(id: result.trackId) }) {
                                Image(systemName: "trash")
                                    .font(.caption)
                            }
                            .buttonStyle(.plain)
                            .foregroundColor(.red)
                        }
                    }
                }
            } else {
                // Initial state
                VStack(spacing: 16) {
                    Image(systemName: "checkmark.shield")
                        .font(.system(size: 48))
                        .foregroundStyle(.secondary)
                    Text("Check your library for missing, corrupt, or damaged files")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                    Button("Start Verification") {
                        verifier.verify()
                    }
                    .buttonStyle(.borderedProminent)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(width: 550, height: 400)
    }
}
