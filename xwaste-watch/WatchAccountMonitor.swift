import CloudKit
import Combine
import CoreData
import Foundation

/// Whether the watch can show the household's data at all, and — when it can
/// but has nothing yet — whether that emptiness is a first sync in flight or a
/// genuinely empty household. The watch is a CloudKit peer with no local-only
/// mode, so an unreachable account is a state to state plainly, not an empty
/// list to leave the user guessing about.
@MainActor
final class WatchAccountMonitor: ObservableObject {

    enum Availability {
        /// Still asking CloudKit; show neither the list nor the excuse yet.
        case checking
        case available
        /// No account, a restricted one, or one CloudKit cannot provision keys
        /// for. All of them mean the same thing to the user: sign in on iPhone.
        case unavailable
    }

    @Published private(set) var availability: Availability = .checking
    /// True until the first CloudKit import finishes, so a cold launch reads as
    /// "loading", not "your household is empty".
    @Published private(set) var isPerformingFirstImport = false

    private var importObserver: (any NSObjectProtocol)?

    init(container: NSPersistentCloudKitContainer, hasLocalData: Bool) {
        isPerformingFirstImport = !hasLocalData
        if !hasLocalData { observeFirstImport(container: container) }

        #if DEBUG
        // The XCUITest suite pins the status so both honest states are
        // assertable without depending on the simulator's iCloud sign-in.
        if let raw = ProcessInfo.processInfo.environment[LaunchSupport.accountStatusEnvironmentKey],
           let value = Int(raw), let status = CKAccountStatus(rawValue: value) {
            apply(status)
            return
        }
        #endif

        CKContainer(identifier: PersistenceController.cloudKitContainerIdentifier)
            .accountStatus { [weak self] status, _ in
                Task { @MainActor in self?.apply(status) }
            }
    }

    deinit {
        if let importObserver { NotificationCenter.default.removeObserver(importObserver) }
    }

    private func apply(_ status: CKAccountStatus) {
        switch status {
        case .available:
            availability = .available
        case .noAccount, .restricted, .temporarilyUnavailable:
            // .temporarilyUnavailable is what an Advanced-Data-Protection
            // account yields when key provisioning cannot complete; from the
            // watch's side it is indistinguishable from having no account.
            availability = .unavailable
            isPerformingFirstImport = false
        case .couldNotDetermine:
            availability = .unavailable
            isPerformingFirstImport = false
        @unknown default:
            availability = .unavailable
            isPerformingFirstImport = false
        }
    }

    private func observeFirstImport(container: NSPersistentCloudKitContainer) {
        importObserver = NotificationCenter.default.addObserver(
            forName: NSPersistentCloudKitContainer.eventChangedNotification,
            object: container, queue: .main
        ) { [weak self] notification in
            let key = NSPersistentCloudKitContainer.eventNotificationUserInfoKey
            guard let event = notification.userInfo?[key] as? NSPersistentCloudKitContainer.Event,
                  event.type == .import, event.endDate != nil else { return }
            Task { @MainActor in self?.finishFirstImport() }
        }
    }

    private func finishFirstImport() {
        isPerformingFirstImport = false
        if let importObserver {
            NotificationCenter.default.removeObserver(importObserver)
            self.importObserver = nil
        }
    }

    /// Any row at all means this install has seen the household's data before,
    /// so a later empty list is real emptiness rather than a pending import.
    static func hasLocalData(in context: NSManagedObjectContext) -> Bool {
        let request = GroceryItem.fetchRequest()
        request.fetchLimit = 1
        return ((try? context.count(for: request)) ?? 0) > 0
    }
}
