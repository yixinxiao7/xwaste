import SwiftUI
import CloudKit
import CoreData

/// The sharing entry point: invite members via the system share sheet, see who
/// is in the household (owner marked), and leave or stop sharing — both behind
/// a confirmation, since neither is reversible from inside the app without a
/// new invitation.
struct HouseholdView: View {
    let household: Household

    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var sharing = SharingController.shared

    @State private var creatingShare = false
    @State private var confirmingStopSharing = false
    @State private var confirmingLeave = false

    var body: some View {
        NavigationStack {
            Form {
                if sharing.accountAvailable == false {
                    // Sharing is unavailable, not broken (and never an error state).
                    Section {
                        Label("Sharing requires iCloud", systemImage: "icloud.slash")
                        Text("The app works fully on this device, but to share your household — or sync your own devices — sign into iCloud in Settings.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                } else if let share = sharing.share {
                    Section("Members") {
                        ForEach(share.participants, id: \.self) { participant in
                            HStack {
                                Text(sharing.participantDisplayName(participant))
                                Spacer()
                                if participant == share.owner {
                                    Text("Owner")
                                        .font(.footnote)
                                        .foregroundStyle(.secondary)
                                } else if participant.acceptanceStatus == .pending {
                                    Text("Invited")
                                        .font(.footnote)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                    Section {
                        ShareLink(item: HouseholdShareItem(share: share, container: sharing.ckContainer),
                                  preview: SharePreview("Shared Grocery Household")) {
                            Label("Invite More People", systemImage: "person.badge.plus")
                        }
                        if sharing.isOwner {
                            Button(role: .destructive) {
                                confirmingStopSharing = true
                            } label: {
                                Label("Stop Sharing", systemImage: "person.2.slash")
                            }
                        } else {
                            Button(role: .destructive) {
                                confirmingLeave = true
                            } label: {
                                Label("Leave Household", systemImage: "rectangle.portrait.and.arrow.right")
                            }
                        }
                    }
                } else {
                    // Never shared yet: an invite prompt, not an empty member list.
                    Section {
                        Text("Share your shopping list and home inventory as one unit, so everyone shops against the same kitchen.")
                        Button {
                            createShare()
                        } label: {
                            if creatingShare {
                                ProgressView()
                            } else {
                                Label("Set Up Sharing", systemImage: "person.badge.plus")
                            }
                        }
                        .disabled(creatingShare)
                    }
                }

                Section {
                } footer: {
                    if sharing.syncing {
                        Label("Syncing…", systemImage: "arrow.triangle.2.circlepath")
                    } else if let error = sharing.lastSyncError {
                        Text("Sync paused: \(error)")
                    }
                }
            }
            .navigationTitle("Household")
            .toolbarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .onAppear {
                sharing.loadShare(for: household)
            }
            .confirmationDialog("Stop sharing this household?",
                                isPresented: $confirmingStopSharing, titleVisibility: .visible) {
                Button("Stop Sharing", role: .destructive) {
                    Task { await sharing.stopSharing() }
                }
            } message: {
                Text("Everyone else loses access to the list and inventory. You keep every item. This cannot be undone without sending a new invitation.")
            }
            .confirmationDialog("Leave this household?",
                                isPresented: $confirmingLeave, titleVisibility: .visible) {
                Button("Leave", role: .destructive) {
                    Task {
                        await sharing.leaveHousehold()
                        dismiss()
                    }
                }
            } message: {
                Text("You will no longer see its list or inventory, and your own household becomes active again. Rejoining requires a new invitation.")
            }
            .alert("Sharing Problem", isPresented: .init(
                get: { sharing.actionError != nil },
                set: { if !$0 { sharing.actionError = nil } }
            )) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(sharing.actionError ?? "")
            }
        }
    }

    private func createShare() {
        creatingShare = true
        Task {
            do {
                try await sharing.createShare(for: household)
            } catch {
                sharing.actionError = "Could not set up sharing: \(error.localizedDescription)"
            }
            creatingShare = false
        }
    }
}

/// Transferable wrapper handing the existing `CKShare` to `ShareLink`, so the
/// system share sheet sends a CloudKit invitation.
struct HouseholdShareItem: Transferable {
    let share: CKShare
    let container: CKContainer

    static var transferRepresentation: some TransferRepresentation {
        CKShareTransferRepresentation { item in
            .existing(item.share, container: item.container)
        }
    }
}
