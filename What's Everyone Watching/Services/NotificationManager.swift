import SwiftUI
import Combine

@MainActor
final class NotificationManager: ObservableObject {
    @Published var message: String?
    private var dismissTask: Task<Void, Never>?

    func show(_ text: String, duration: TimeInterval = 5.0) {
        dismissTask?.cancel()
        message = text
        dismissTask = Task {
            try? await Task.sleep(nanoseconds: UInt64(duration * 1_000_000_000))
            withAnimation {
                self.message = nil
            }
        }
    }

    func dismiss() {
        dismissTask?.cancel()
        message = nil
    }
}
