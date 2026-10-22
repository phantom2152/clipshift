import SwiftUI

/// One small message line shown above the lists (replaces modal alerts for minor problems).
@MainActor
final class NoticeCenter: ObservableObject {
    static let shared = NoticeCenter()

    @Published private(set) var message: String?
    private var clearTask: Task<Void, Never>?

    private init() {}

    func post(_ text: String) {
        message = text
        clearTask?.cancel()
        clearTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(8))
            if !Task.isCancelled { self?.message = nil }
        }
    }

    func dismiss() {
        clearTask?.cancel()
        message = nil
    }
}

struct NoticeBanner: View {
    @ObservedObject private var center = NoticeCenter.shared

    var body: some View {
        if let text = center.message {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "info.circle.fill").foregroundStyle(.orange)
                Text(text)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
                Button {
                    center.dismiss()
                } label: {
                    Image(systemName: "xmark")
                }
                .buttonStyle(.borderless)
                .help("Dismiss")
            }
            .padding(10)
            .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
        }
    }
}
