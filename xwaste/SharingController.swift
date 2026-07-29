import CloudKit
import Combine
import CoreData

/// Wraps share creation, participant lookup, stop-sharing, and leaving for the
/// `Household` object, plus the iCloud account check and an unobtrusive sync
/// state derived from container events.
final class SharingController: ObservableObject {
    /// One instance for the whole app: share state must outlive any single
    /// presentation of `HouseholdView`, because the local share cache lags the
    /// server after a stop/leave and a fresh controller would trust it.
    static let shared = SharingController()

    @Published private(set) var share: CKShare?

    /// Shares deleted server-side this session. `fetchShares(matching:)` reads
    /// the local mirror, which keeps returning them until the next CloudKit
    /// import; anything in this set is treated as already gone.
    private var deletedShareRecordIDs: Set<CKRecord.ID> = []
    /// nil while the account check is in flight.
    @Published private(set) var accountAvailable: Bool?
    @Published private(set) var syncing = false
    @Published private(set) var lastSyncError: String?
    @Published var actionError: String?

    private let persistence = PersistenceController.shared
    private var eventObserver: (any NSObjectProtocol)?

    var container: NSPersistentCloudKitContainer { persistence.container }
    var ckContainer: CKContainer { CKContainer(identifier: PersistenceController.cloudKitContainerIdentifier) }

    init() {
        observeSyncEvents()
        refreshAccountStatus()
    }

    deinit {
        if let eventObserver {
            NotificationCenter.default.removeObserver(eventObserver)
        }
    }

    /// The current user owns the household they are sharing (as opposed to
    /// participating in someone else's).
    var isOwner: Bool {
        guard let share else { return true }
        return share.currentUserParticipant == share.owner
    }

    func refreshAccountStatus() {
        Task {
            let status = try? await ckContainer.accountStatus()
            accountAvailable = status == .available
        }
    }

    func loadShare(for household: Household) {
        let fetched = (try? container.fetchShares(matching: [household.objectID]))?[household.objectID]
        if let fetched, deletedShareRecordIDs.contains(fetched.recordID) {
            share = nil
        } else {
            share = fetched
        }
    }

    /// Creates the `CKShare` for the household — the whole graph beneath it
    /// (list and inventory together) travels with the share.
    ///
    /// The container calls run in a detached task with completion-handler
    /// APIs: `share(_:to:)` blocks its calling thread, and this project's
    /// caller's-actor async semantics would put an awaited call on the main
    /// actor — freezing the UI and deadlocking against the completion delivery.
    func createShare(for household: Household) async throws {
        let container = self.container
        let privateStore = persistence.privatePersistentStore
        let newShare = try await Task.detached {
            let created: CKShare = try await withCheckedThrowingContinuation { continuation in
                container.share([household], to: nil) { _, share, _, error in
                    if let share {
                        continuation.resume(returning: share)
                    } else {
                        continuation.resume(throwing: error ?? CKError(.internalError))
                    }
                }
            }
            created[CKShare.SystemFieldKey.title] = "Shared Grocery Household"
            if let privateStore {
                container.persistUpdatedShare(created, in: privateStore) { _, error in
                    if let error {
                        print("Persisting updated share failed: \(error)")
                    }
                }
            }
            return created
        }.value
        share = newShare
    }

    /// Owner only: deleting the share record revokes every participant's
    /// access; the owner's data stays intact in the private store.
    func stopSharing() async {
        guard let share else { return }
        do {
            _ = try await ckContainer.privateCloudDatabase.deleteRecord(withID: share.recordID)
            deletedShareRecordIDs.insert(share.recordID)
            self.share = nil
        } catch {
            actionError = "Could not stop sharing: \(error.localizedDescription)"
        }
    }

    /// Participant only: removing the shared zone from the shared database
    /// leaves the household, then the personal household becomes active again.
    func leaveHousehold() async {
        guard let share else { return }
        do {
            _ = try await ckContainer.sharedCloudDatabase.deleteRecordZone(withID: share.recordID.zoneID)
            deletedShareRecordIDs.insert(share.recordID)
            self.share = nil
            persistence.activatePersonalHousehold()
        } catch {
            actionError = "Could not leave the household: \(error.localizedDescription)"
        }
    }

    func participantDisplayName(_ participant: CKShare.Participant) -> String {
        if let components = participant.userIdentity.nameComponents {
            let name = PersonNameComponentsFormatter().string(from: components)
            if !name.isEmpty { return name }
        }
        if let email = participant.userIdentity.lookupInfo?.emailAddress { return email }
        if let phone = participant.userIdentity.lookupInfo?.phoneNumber { return phone }
        return "Household member"
    }

    /// Pending uploads / imports, surfaced quietly — never blocks anything.
    private func observeSyncEvents() {
        eventObserver = NotificationCenter.default.addObserver(
            forName: NSPersistentCloudKitContainer.eventChangedNotification,
            object: nil, queue: .main
        ) { [weak self] note in
            guard let self,
                  let event = note.userInfo?[NSPersistentCloudKitContainer.eventNotificationUserInfoKey]
                    as? NSPersistentCloudKitContainer.Event else { return }
            let inFlight = event.endDate == nil
            let errorText = event.error?.localizedDescription
            let controller = self
            Task { @MainActor in
                controller.syncing = inFlight
                if let errorText { controller.lastSyncError = errorText } else if !inFlight { controller.lastSyncError = nil }
            }
        }
    }
}
