import SwiftUI

struct Hint: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text).font(.caption).foregroundStyle(.secondary)
    }
}

struct ResetSection: View {
    var title = "Reset This Tab to Defaults"
    let action: () -> Void
    var body: some View {
        Section {
            HStack {
                Spacer()
                Button(title, action: action)
            }
        }
    }
}

struct IntRow: View {
    let title: String
    var unit: String? = nil
    @Binding var value: Int

    var body: some View {
        LabeledContent(title) {
            HStack(spacing: 6) {
                TextField("", value: $value, format: .number.grouping(.never))
                    .textFieldStyle(.roundedBorder)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 80)
                if let unit { Text(unit).foregroundStyle(.secondary) }
            }
        }
    }
}

/// High / Balanced / Small number fields in one row.
struct TripleRow: View {
    let title: String
    var unit: String? = nil
    @Binding var value: PerQuality<Int>

    var body: some View {
        LabeledContent(title) {
            HStack(spacing: 10) {
                field("High", $value.high)
                field("Balanced", $value.medium)
                field("Small", $value.small)
                if let unit { Text(unit).foregroundStyle(.secondary) }
            }
        }
    }

    private func field(_ label: String, _ binding: Binding<Int>) -> some View {
        HStack(spacing: 4) {
            Text(label).font(.caption).foregroundStyle(.secondary)
            TextField("", value: binding, format: .number.grouping(.never))
                .textFieldStyle(.roundedBorder)
                .multilineTextAlignment(.trailing)
                .frame(width: 54)
        }
    }
}

/// A picker over fixed integer choices. A stored value that isn't in the list is kept
/// and shown as "Custom", so nothing is silently changed.
struct IntChoiceRow: View {
    struct Choice: Identifiable {
        let value: Int
        let label: String
        var id: Int { value }
    }

    let title: String
    let choices: [Choice]
    @Binding var value: Int

    var body: some View {
        Picker(title, selection: $value) {
            if !choices.contains(where: { $0.value == value }) {
                Text("Custom (\(value))").tag(value)
            }
            ForEach(choices) { Text($0.label).tag($0.value) }
        }
    }
}

/// A folder path with Choose… and Reset buttons.
struct FolderRow: View {
    let emptyLabel: String
    let resetTitle: String
    @Binding var path: String

    var body: some View {
        HStack {
            Text(path.isEmpty ? emptyLabel : (path as NSString).abbreviatingWithTildeInPath)
                .lineLimit(1)
                .truncationMode(.middle)
                .foregroundStyle(.secondary)
            Spacer()
            Button("Choose…") {
                if let url = Panels.pickFolder() { path = url.path }
            }
            if !path.isEmpty {
                Button(resetTitle) { path = "" }
            }
        }
    }
}
