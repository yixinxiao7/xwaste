import CoreData
import CloudKit
import Combine

/// Wraps `NSPersistentCloudKitContainer` — the CloudKit-capable container type —
/// with the private store mirroring to the app's CloudKit container and a
/// second store at `.shared` scope for accepted households. The app must stay
/// fully usable with no iCloud account: store loading succeeds locally either
/// way, and mirroring simply stays idle.
final class PersistenceController: ObservableObject {
    static let shared = PersistenceController()

    static let cloudKitContainerIdentifier = "iCloud.com.yixinxiao.nomorewaste"
    private static let activeHouseholdIDKey = "activeHouseholdID"

    let container: NSPersistentCloudKitContainer
    private let inMemory: Bool

    /// The `.private`-scope store holding the personal household.
    private(set) var privatePersistentStore: NSPersistentStore?
    /// The `.shared`-scope store where accepted households arrive; nil for
    /// in-memory stacks. `activeHousehold` resolution checks it so joining a
    /// household only changes what `activeHousehold` points at, not any fetch.
    private(set) var sharedPersistentStore: NSPersistentStore?

    init(inMemory: Bool = false) {
        self.inMemory = inMemory
        container = NSPersistentCloudKitContainer(name: "XWaste")

        guard let privateDescription = container.persistentStoreDescriptions.first else {
            fatalError("Missing persistent store description")
        }
        var sharedStoreURL: URL?
        if inMemory {
            privateDescription.url = URL(fileURLWithPath: "/dev/null")
            privateDescription.cloudKitContainerOptions = nil
        } else {
            // The store files keep their pre-rename (NoMoreWaste) filenames:
            // the model name default would be XWaste.sqlite, which existing
            // installs don't have — switching would strand their local data.
            privateDescription.url = privateDescription.url!.deletingLastPathComponent()
                .appendingPathComponent("NoMoreWaste.sqlite")
            // History tracking and remote-change notifications must be on from
            // the first release; retrofitting them after data exists is painful.
            privateDescription.setOption(true as NSNumber, forKey: NSPersistentHistoryTrackingKey)
            privateDescription.setOption(true as NSNumber, forKey: NSPersistentStoreRemoteChangeNotificationPostOptionKey)
            let privateOptions = NSPersistentCloudKitContainerOptions(
                containerIdentifier: Self.cloudKitContainerIdentifier
            )
            privateOptions.databaseScope = .private
            privateDescription.cloudKitContainerOptions = privateOptions

            // Second store at .shared scope in its own SQLite file, so accepted
            // households mirror alongside — never into — the private data.
            // Fetches see both stores; the activeHousehold predicate keeps the
            // two households from ever appearing merged.
            let url = privateDescription.url!.deletingLastPathComponent()
                .appendingPathComponent("NoMoreWaste-shared.sqlite")
            let sharedDescription = NSPersistentStoreDescription(url: url)
            sharedDescription.setOption(true as NSNumber, forKey: NSPersistentHistoryTrackingKey)
            sharedDescription.setOption(true as NSNumber, forKey: NSPersistentStoreRemoteChangeNotificationPostOptionKey)
            let sharedOptions = NSPersistentCloudKitContainerOptions(
                containerIdentifier: Self.cloudKitContainerIdentifier
            )
            sharedOptions.databaseScope = .shared
            sharedDescription.cloudKitContainerOptions = sharedOptions
            container.persistentStoreDescriptions.append(sharedDescription)
            sharedStoreURL = url
        }

        container.loadPersistentStores { _, error in
            if let error {
                fatalError("Failed to load persistent store: \(error)")
            }
        }
        if let privateURL = privateDescription.url {
            privatePersistentStore = container.persistentStoreCoordinator.persistentStore(for: privateURL)
        }
        if let sharedStoreURL {
            sharedPersistentStore = container.persistentStoreCoordinator.persistentStore(for: sharedStoreURL)
        }
        container.viewContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
        container.viewContext.automaticallyMergesChangesFromParent = true
        activeHousehold = resolveActiveHousehold()
    }

    /// In-memory variant for SwiftUI previews, seeded with a few items.
    static let preview: PersistenceController = {
        let controller = PersistenceController(inMemory: true)
        let context = controller.container.viewContext
        let household: Household = controller.activeHousehold
        GroceryItem.create(name: "Broccoli", quantity: 1, location: .shoppingList, household: household, in: context)
        GroceryItem.create(name: "Milk", quantity: 2, location: .shoppingList, household: household, in: context)
        GroceryItem.create(name: "Onion", quantity: 3, location: .atHome, household: household, in: context)
        try? context.save()
        return controller
    }()

    // MARK: - Active household

    /// The household every item fetch in the app scopes to. Only what this
    /// points at changes when the user joins or leaves a shared household.
    /// Set once in init, before anything can read it.
    @Published private(set) var activeHousehold: Household!

    func activate(_ household: Household) {
        activeHousehold = household
        persistActiveHouseholdID(household)
    }

    /// Back to the personal (private-store) household after leaving a shared one.
    func activatePersonalHousehold() {
        let request = Household.fetchRequest()
        request.sortDescriptors = [NSSortDescriptor(key: "createdAt", ascending: true)]
        let households = (try? container.viewContext.fetch(request)) ?? []
        if let personal = households.first(where: { $0.objectID.persistentStore !== sharedPersistentStore }) {
            activate(personal)
        }
    }

    // MARK: - Invitation acceptance

    private var remoteChangeObserver: (any NSObjectProtocol)?

    /// Called from the scene delegate when the user opens an invitation.
    func acceptShareInvitation(_ metadata: CKShare.Metadata) {
        guard let sharedStore = sharedPersistentStore else { return }
        container.acceptShareInvitations(from: [metadata], into: sharedStore) { _, error in
            if let error {
                print("Share acceptance failed: \(error)")
                return
            }
            Task { @MainActor in
                PersistenceController.shared.activateSharedHouseholdWhenAvailable()
            }
        }
    }

    /// The shared household arrives with the first import after acceptance;
    /// switch to it as soon as it exists so the participant sees the shared
    /// list and inventory rather than their own former local data.
    func activateSharedHouseholdWhenAvailable() {
        guard !activateSharedHouseholdIfPresent(), remoteChangeObserver == nil else { return }
        remoteChangeObserver = NotificationCenter.default.addObserver(
            forName: .NSPersistentStoreRemoteChange, object: nil, queue: .main
        ) { _ in
            Task { @MainActor in
                let controller = PersistenceController.shared
                if controller.activateSharedHouseholdIfPresent(),
                   let observer = controller.remoteChangeObserver {
                    NotificationCenter.default.removeObserver(observer)
                    controller.remoteChangeObserver = nil
                }
            }
        }
    }

    @discardableResult
    private func activateSharedHouseholdIfPresent() -> Bool {
        guard let sharedStore = sharedPersistentStore else { return false }
        let request = Household.fetchRequest()
        let households = (try? container.viewContext.fetch(request)) ?? []
        guard let shared = households.first(where: { $0.objectID.persistentStore === sharedStore }) else {
            return false
        }
        activate(shared)
        return true
    }

    /// Launch resolution: the persisted choice wins (so the active household
    /// never flips when a sync arrives mid-session), then a household living in
    /// the shared store (an accepted invitation), then the personal one —
    /// created on first launch with no prompt or setup step.
    private func resolveActiveHousehold() -> Household {
        let context = container.viewContext
        let request = Household.fetchRequest()
        request.sortDescriptors = [NSSortDescriptor(key: "createdAt", ascending: true)]
        let households = (try? context.fetch(request)) ?? []

        if let persistedID = UserDefaults.standard.string(forKey: Self.activeHouseholdIDKey),
           let persisted = households.first(where: { $0.id?.uuidString == persistedID }) {
            return persisted
        }
        if let sharedStore = sharedPersistentStore,
           let joined = households.first(where: { $0.objectID.persistentStore === sharedStore }) {
            persistActiveHouseholdID(joined)
            return joined
        }
        if let personal = households.first {
            persistActiveHouseholdID(personal)
            return personal
        }

        let household = Household(context: context)
        household.id = UUID()
        household.createdAt = Date()
        try? context.save()
        persistActiveHouseholdID(household)
        return household
    }

    private func persistActiveHouseholdID(_ household: Household) {
        guard !inMemory else { return }
        UserDefaults.standard.set(household.id?.uuidString, forKey: Self.activeHouseholdIDKey)
    }

    // MARK: - CloudKit schema

    #if DEBUG
    /// Pushes the model to the CloudKit **development** environment. Opt-in
    /// only: launch once with the PUSH_CK_SCHEMA=1 environment variable after
    /// the team is set up in Xcode. Wrapped in DEBUG so it cannot exist in a
    /// shipping build.
    func pushCloudKitDevelopmentSchema() {
        do {
            try container.initializeCloudKitSchema(options: [])
            print("CloudKit development schema push succeeded")
        } catch {
            print("CloudKit schema push failed: \(error)")
        }
    }
    #endif
}
