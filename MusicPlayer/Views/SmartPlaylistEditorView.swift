import SwiftUI

struct SmartPlaylistEditorView: View {
    @Binding var isPresented: Bool
    var existingPlaylist: Playlist?
    var onSave: ((String, SmartPlaylistCriteria) -> Void)?

    @State private var name: String = ""
    @State private var criteria = SmartPlaylistCriteria()
    @State private var hasLimit: Bool = false
    @State private var limitCount: String = "25"
    @State private var previewCount: Int = 0

    init(isPresented: Binding<Bool>, existingPlaylist: Playlist? = nil, onSave: ((String, SmartPlaylistCriteria) -> Void)? = nil) {
        self._isPresented = isPresented
        self.existingPlaylist = existingPlaylist
        self.onSave = onSave
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text(existingPlaylist == nil ? "New Smart Playlist" : "Edit Smart Playlist")
                    .font(.headline)
                Spacer()
                Button(action: { isPresented = false }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding()

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // Name field
                    HStack {
                        Text("Name:")
                            .frame(width: 80, alignment: .trailing)
                        TextField("Smart Playlist Name", text: $name)
                            .textFieldStyle(.roundedBorder)
                    }

                    Divider()

                    // Match type
                    HStack {
                        Text("Match")
                            .frame(width: 80, alignment: .trailing)
                        Picker("", selection: $criteria.matchAll) {
                            Text("all").tag(true)
                            Text("any").tag(false)
                        }
                        .pickerStyle(.segmented)
                        .frame(width: 100)
                        Text("of the following rules:")
                    }

                    // Rules
                    VStack(spacing: 8) {
                        ForEach($criteria.rules) { $rule in
                            SmartPlaylistRuleRow(rule: $rule, onDelete: {
                                criteria.rules.removeAll { $0.id == rule.id }
                                updatePreview()
                            })
                        }
                    }

                    // Add rule button
                    Button(action: addRule) {
                        Label("Add Rule", systemImage: "plus.circle")
                    }
                    .buttonStyle(.borderless)

                    Divider()

                    // Limit
                    HStack {
                        Toggle("Limit to", isOn: $hasLimit)
                            .toggleStyle(.checkbox)
                            .onChange(of: hasLimit) { _, newValue in
                                criteria.limit = newValue ? Int(limitCount) : nil
                                updatePreview()
                            }

                        if hasLimit {
                            TextField("", text: $limitCount)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 60)
                                .onChange(of: limitCount) { _, newValue in
                                    criteria.limit = Int(newValue)
                                    updatePreview()
                                }

                            Text("tracks, sorted by")

                            Picker("", selection: $criteria.orderBy) {
                                ForEach(SmartPlaylistOrder.allCases, id: \.self) { order in
                                    Text(order.displayName).tag(order)
                                }
                            }
                            .frame(width: 180)
                        }
                    }

                    // Preview
                    HStack {
                        Image(systemName: "info.circle")
                            .foregroundColor(.secondary)
                        Text("Matches \(previewCount) tracks")
                            .foregroundColor(.secondary)
                            .font(.subheadline)
                    }
                }
                .padding()
            }
            .onChange(of: criteria) { _, _ in
                updatePreview()
            }

            Divider()

            // Footer buttons
            HStack {
                Spacer()
                Button("Cancel") { isPresented = false }
                    .keyboardShortcut(.cancelAction)
                Button("Save") { save() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || criteria.rules.isEmpty)
            }
            .padding()
        }
        .frame(width: 600, height: 500)
        .onAppear {
            if let playlist = existingPlaylist {
                name = playlist.name
                if let json = playlist.smartCriteria,
                   let data = json.data(using: .utf8),
                   let decoded = try? JSONDecoder().decode(SmartPlaylistCriteria.self, from: data) {
                    criteria = decoded
                    hasLimit = criteria.limit != nil
                    if let limit = criteria.limit {
                        limitCount = "\(limit)"
                    }
                }
            }
            if criteria.rules.isEmpty {
                addRule()
            }
            updatePreview()
        }
    }

    private func addRule() {
        let rule = SmartPlaylistRule(
            field: .artistName,
            comparison: .contains,
            value: ""
        )
        criteria.rules.append(rule)
    }

    private func updatePreview() {
        previewCount = PlaylistDAO().getSmartPlaylistTrackCount(criteria: criteria)
    }

    private func save() {
        let trimmedName = name.trimmingCharacters(in: .whitespaces)
        guard !trimmedName.isEmpty, !criteria.rules.isEmpty else { return }

        if !hasLimit {
            criteria.limit = nil
        }

        onSave?(trimmedName, criteria)
        isPresented = false
    }
}

struct SmartPlaylistRuleRow: View {
    @Binding var rule: SmartPlaylistRule
    var onDelete: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Picker("", selection: $rule.field) {
                ForEach(SmartPlaylistField.allCases, id: \.self) { field in
                    Text(field.displayName).tag(field)
                }
            }
            .frame(width: 120)
            .onChange(of: rule.field) { _, newField in
                // Reset comparison to first available for new field
                if let first = newField.availableComparisons.first {
                    rule.comparison = first
                }
                if newField.isBool {
                    rule.value = "true"
                } else {
                    rule.value = ""
                }
            }

            Picker("", selection: $rule.comparison) {
                ForEach(rule.field.availableComparisons, id: \.self) { comp in
                    Text(comp.displayName).tag(comp)
                }
            }
            .frame(width: 140)

            if rule.field.isBool {
                Picker("", selection: $rule.value) {
                    Text("Yes").tag("true")
                    Text("No").tag("false")
                }
                .frame(width: 80)
            } else if rule.field.isDate {
                HStack(spacing: 4) {
                    TextField("", text: $rule.value)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 60)
                    Text("days")
                        .foregroundColor(.secondary)
                }
            } else {
                TextField(rule.field.isNumeric ? "0" : "value", text: $rule.value)
                    .textFieldStyle(.roundedBorder)
            }

            Button(action: onDelete) {
                Image(systemName: "minus.circle.fill")
                    .foregroundColor(.red)
            }
            .buttonStyle(.plain)
        }
    }
}
