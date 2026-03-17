import SwiftUI

struct EffectSlotView: View {
    let index: Int
    let slot: (any EffectSlot)?
    let onAdd: () -> Void
    let onRemove: () -> Void
    let onBypass: () -> Void
    let onOpenUI: () -> Void
    var isSelected: Bool = false

    var body: some View {
        if let slot = slot {
            filledSlotRow(slot)
        } else {
            emptySlotRow
        }
    }

    // MARK: - Filled Slot

    private func filledSlotRow(_ slot: any EffectSlot) -> some View {
        HStack(spacing: 8) {
            // Drag handle
            Image(systemName: "line.3.horizontal")
                .foregroundStyle(.secondary)
                .font(.caption)
                .frame(width: 16)

            // Slot number
            Text("\(index + 1)")
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 14)

            // Name + manufacturer badge
            VStack(alignment: .leading, spacing: 1) {
                Text(slot.displayName)
                    .font(.system(size: 12, weight: .medium))
                    .strikethrough(slot.isBypassed)
                    .lineLimit(1)

                Text(slot.manufacturer)
                    .font(.caption2)
                    .foregroundStyle(slot.slotType == .auPlugin ? Color.blue : Color.orange)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            // Open UI button (AU plugins only)
            if slot.slotType == .auPlugin {
                Button(action: onOpenUI) {
                    Image(systemName: "slider.horizontal.3")
                        .font(.caption)
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.blue)
                .help("Open Plugin UI")
            }

            // Bypass toggle
            Button(action: onBypass) {
                Image(systemName: "power")
                    .font(.caption)
                    .foregroundStyle(slot.isBypassed ? .secondary : Color.orange)
            }
            .buttonStyle(.borderless)
            .help(slot.isBypassed ? "Enable" : "Bypass")

            // Remove button
            Button(action: onRemove) {
                Image(systemName: "xmark")
                    .font(.caption)
            }
            .buttonStyle(.borderless)
            .foregroundStyle(.secondary)
            .help("Remove")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(isSelected ? Color.accentColor.opacity(0.1) : Color.clear)
        .opacity(slot.isBypassed ? 0.6 : 1.0)
        .cornerRadius(6)
    }

    // MARK: - Empty Slot

    private var emptySlotRow: some View {
        Button(action: onAdd) {
            HStack(spacing: 6) {
                Image(systemName: "plus")
                    .font(.caption)
                Text("Add Effect")
                    .font(.caption)
                Spacer()
                Text("\(index + 1)")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(Color(nsColor: .tertiaryLabelColor))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                    .foregroundStyle(Color.secondary.opacity(0.4))
            )
        }
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
    }
}
