import SwiftUI
import UniformTypeIdentifiers

// A Identifiable wrapper around Int slot index — avoids extending Int: Identifiable
private struct SlotIndex: Identifiable {
    let id: Int
}

struct EffectChainView: View {
    @ObservedObject private var chainManager = EffectChainManager.shared
    @Binding var expandedSlotIndex: Int?

    @State private var addingSlot: SlotIndex? = nil
    @State private var draggingIndex: Int? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                Text("Effect Chain")
                    .font(.headline)
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            Divider()

            ScrollView {
                VStack(spacing: 4) {
                    ForEach(0..<8, id: \.self) { index in
                        let slot = chainManager.slots[index]
                        let isSelected = expandedSlotIndex == index

                        EffectSlotView(
                            index: index,
                            slot: slot,
                            onAdd: {
                                addingSlot = SlotIndex(id: index)
                            },
                            onRemove: {
                                chainManager.removeSlot(at: index)
                                if expandedSlotIndex == index { expandedSlotIndex = nil }
                            },
                            onBypass: {
                                chainManager.toggleBypass(at: index)
                            },
                            onOpenUI: {
                                openAUPluginUI(at: index)
                            },
                            isSelected: isSelected
                        )
                        .contentShape(Rectangle())
                        .onTapGesture {
                            guard let slot = slot else { return }
                            if slot.slotType == .auPlugin {
                                openAUPluginUI(at: index)
                            } else {
                                expandedSlotIndex = (expandedSlotIndex == index) ? nil : index
                            }
                        }
                        .onDrag {
                            draggingIndex = index
                            return NSItemProvider(object: "\(index)" as NSString)
                        }
                        .onDrop(of: [.plainText], delegate: SlotDropDelegate(
                            targetIndex: index,
                            draggingIndex: $draggingIndex,
                            chainManager: chainManager
                        ))
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
            }
        }
        .popover(item: $addingSlot) { slotIndex in
            AUPluginPickerView(
                slotIndex: slotIndex.id,
                onSelectBuiltIn: { type in
                    chainManager.insertBuiltIn(type: type, at: slotIndex.id)
                    addingSlot = nil
                    expandedSlotIndex = slotIndex.id
                },
                onSelectAU: { pluginInfo in
                    chainManager.insertAUPlugin(
                        description: pluginInfo.componentDescription,
                        name: pluginInfo.name,
                        manufacturer: pluginInfo.manufacturerName,
                        at: slotIndex.id
                    ) {}
                    addingSlot = nil
                }
            )
        }
    }

    private func openAUPluginUI(at index: Int) {
        guard let slot = chainManager.slots[index] as? AUPluginSlot else { return }
        if let engine = PlayerManager.shared.currentEngine {
            AUPluginWindowManager.shared.openPluginUI(for: slot, engine: engine)
        } else {
            // No active player — open fallback panel (plugin not yet instantiated)
            AUPluginWindowManager.shared.openPluginUI(for: slot, engine: nil)
        }
    }
}

// MARK: - Drop Delegate

private struct SlotDropDelegate: DropDelegate {
    let targetIndex: Int
    @Binding var draggingIndex: Int?
    let chainManager: EffectChainManager

    func performDrop(info: DropInfo) -> Bool {
        guard let source = draggingIndex, source != targetIndex else { return false }
        chainManager.move(from: source, to: targetIndex)
        draggingIndex = nil
        return true
    }

    func dropEntered(info: DropInfo) {}

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }
}
