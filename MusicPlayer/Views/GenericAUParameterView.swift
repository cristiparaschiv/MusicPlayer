import SwiftUI
import AVFoundation
import AudioToolbox
import AppKit

// MARK: - AUViewControllerWrapper

/// Wraps a plugin's NSViewController for use inside SwiftUI.
struct AUViewControllerWrapper: NSViewControllerRepresentable {
    let viewController: NSViewController

    func makeNSViewController(context: Context) -> NSViewController {
        viewController
    }

    func updateNSViewController(_ nsViewController: NSViewController, context: Context) {}
}

// MARK: - AUParameterSlider

/// A single row showing a parameter name, formatted value, and a slider.
struct AUParameterSlider: View {
    let parameter: AUParameter

    @State private var value: Float

    init(parameter: AUParameter) {
        self.parameter = parameter
        _value = State(initialValue: parameter.value)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(parameter.displayName)
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)
                Spacer()
                Text(formattedValue)
                    .font(.system(size: 11).monospacedDigit())
                    .foregroundStyle(.secondary)
                    .frame(minWidth: 50, alignment: .trailing)
            }

            Slider(
                value: Binding(
                    get: { Double(value) },
                    set: { newVal in
                        value = Float(newVal)
                        parameter.value = Float(newVal)
                    }
                ),
                in: Double(parameter.minValue)...Double(parameter.maxValue)
            )
        }
        .padding(.vertical, 2)
    }

    private var formattedValue: String {
        let v = Double(value)
        if abs(v) >= 1000 { return String(format: "%.0f", v) }
        if abs(v) >= 10 { return String(format: "%.1f", v) }
        return String(format: "%.2f", v)
    }
}

// MARK: - GenericAUParameterView

/// Fallback SwiftUI UI for AU plugins that don't provide a custom view controller.
struct GenericAUParameterView: View {
    let audioUnit: AUAudioUnit

    private var parameters: [AUParameter] {
        guard let tree = audioUnit.parameterTree else { return [] }
        return flattenParameters(tree.children)
    }

    var body: some View {
        if parameters.isEmpty {
            VStack(spacing: 12) {
                Image(systemName: "slider.horizontal.3")
                    .font(.system(size: 40))
                    .foregroundStyle(.secondary)
                Text("No UI available")
                    .font(.headline)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding()
        } else {
            ScrollView {
                LazyVStack(spacing: 8) {
                    ForEach(parameters, id: \.address) { param in
                        AUParameterSlider(parameter: param)
                            .padding(.horizontal)
                    }
                }
                .padding(.vertical, 8)
            }
        }
    }

    private func flattenParameters(_ nodes: [AUParameterNode]) -> [AUParameter] {
        var result: [AUParameter] = []
        for node in nodes {
            if let param = node as? AUParameter {
                result.append(param)
            } else if let group = node as? AUParameterGroup {
                result.append(contentsOf: flattenParameters(group.children))
            }
        }
        return result
    }
}
