import SwiftUI

/// What the phone shows as a bottom banner. On a 40 mm screen an overlay banner
/// *is* the screen, so the watch presents the same `CheckOffUndo` full-screen
/// and gets out of the way after ~5 seconds.
struct WatchConfirmation: Identifiable {
    let id = UUID()
    let message: String
    /// nil once there is nothing left to reverse — the changed-elsewhere
    /// message keeps the same presentation but drops the button.
    var undo: CheckOffUndo?
}

struct WatchConfirmationView: View {
    let confirmation: WatchConfirmation
    let onUndo: (CheckOffUndo) -> Void
    let onDismiss: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "checkmark.circle.fill")
                .font(.title2)
                .foregroundStyle(.green)
            Text(confirmation.message)
                .font(.headline)
                .multilineTextAlignment(.center)
                .accessibilityIdentifier("confirmation-message")
            if let undo = confirmation.undo {
                Button("Undo") { onUndo(undo) }
                    .accessibilityIdentifier("undo-button")
            }
            Button("Done", action: onDismiss)
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("confirmation-done")
        }
        .padding()
        // Deliberately no container-level accessibility identifier: SwiftUI
        // pushes one down onto every child, which would erase the per-element
        // identifiers the suite queries.
    }
}
