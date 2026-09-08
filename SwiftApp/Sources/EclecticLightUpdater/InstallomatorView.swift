import SwiftUI

struct InstallomatorView: View {
    @ObservedObject private var model = InstallomatorModel.shared
    @State private var search = ""
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Installomator").font(.title2.bold())
            Text(model.path ?? "Not installed").font(.caption)
            HStack {
                Button("Install Installomator") { Task { await model.setup() } }
                Button("Refresh Labels") { Task { await model.refresh() } }
                TextField("Search labels", text: $search)
            }.disabled(model.busy)
            List(model.labels.filter { search.isEmpty || $0.localizedCaseInsensitiveContains(search) }, id: \.self) { label in
                Toggle(label, isOn: Binding(get: { model.selected.contains(label) }, set: {
                    if $0 { model.selected.insert(label) } else { model.selected.remove(label) }
                })).disabled(model.busy)
            }
            Text("Selected: " + model.selected.sorted().joined(separator: ", "))
                .font(.caption).lineLimit(3).help(model.selected.sorted().joined(separator: ", "))
            HStack {
                Button("Install Selected (\(model.selected.count))") { Task { await model.installSelected() } }
                    .disabled(model.busy || model.selected.isEmpty)
                Button("Clear Selection") { model.selected = [] }.disabled(model.busy)
                if model.busy {
                    ProgressView().controlSize(.small)
                    Button("Stop After Current") { model.stopRequested = true }
                }
            }
            Text(model.status).font(.callout)
            ScrollView {
                Text(model.output).font(.system(.caption, design: .monospaced)).textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }.frame(height: 140)
        }.padding().frame(minWidth: 760, minHeight: 640)
        .task { await model.refresh() }
    }
}
