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
    private static let autoCreatedKey = "activeHouseholdWasAutoCreated"

    let container: NSPersistentCloudKitContainer
    private let inMemory: Bool

    /// The `.private`-scope store holding the personal household.
    private(set) var privatePersistentStore: NSPersistentStore?
    /// The `.shared`-scope store where accepted households arrive; nil for
    /// in-memory stacks. `activeHousehold` resolution checks it so joining a
    /// household only changes what `activeHousehold` points at, not any fetch.
    private(set) var sharedPersistentStore: NSPersistentStore?

    /// Loaded exactly once and handed to every container. `init(name:)` would
    /// load a *new* `NSManagedObjectModel` per instance, and two loaded models
    /// declaring the same entities make Core Data unable to map an entity to
    /// its managed-object subclass ("Failed to find a unique match…"), which
    /// throws as soon as a second stack exists — previews plus the app, or one
    /// per unit test.
    private static let managedObjectModel: NSManagedObjectModel = {
        guard let url = Bundle(for: GroceryItem.self).url(forResource: "XWaste", withExtension: "momd"),
              let model = NSManagedObjectModel(contentsOf: url) else {
            fatalError("Missing XWaste managed object model")
        }
        return model
    }()

    init(inMemory: Bool = false) {
        self.inMemory = inMemory
        container = NSPersistentCloudKitContainer(name: "XWaste",
                                                  managedObjectModel: Self.managedObjectModel)

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
        if !inMemory, UserDefaults.standard.bool(forKey: Self.autoCreatedKey) {
            activeHouseholdWasAutoCreated = true
        }
        activeHousehold = resolveActiveHousehold()
        // A previously-provisional choice may be resolvable already, or only
        // once the next import lands.
        adoptSyncedHouseholdIfPresent()
        observeForAdoption()
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

    /// True when `activeHousehold` is one this install invented because the
    /// local store was empty at launch — not one the user has ever used. A
    /// fresh install on a second device always hits this: Core Data has
    /// nothing yet, CloudKit has not imported yet, so a household gets created
    /// that the real data will never belong to. Until an import proves
    /// otherwise, that choice stays provisional.
    private(set) var activeHouseholdWasAutoCreated = false

    private var householdAdoptionObserver: (any NSObjectProtocol)?

    func activate(_ household: Household) {
        activeHousehold = household
        activeHouseholdWasAutoCreated = false
        persistAutoCreatedFlag()
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

    /// Swaps a provisionally-created household for the real one as soon as
    /// CloudKit delivers it. Without this a second device shows an empty list
    /// forever: its own empty household stays active while the household that
    /// actually owns the items sits unreferenced in the same store.
    @discardableResult
    func adoptSyncedHouseholdIfPresent() -> Bool {
        guard activeHouseholdWasAutoCreated, let current = activeHousehold else { return false }
        let context = container.viewContext
        let request = Household.fetchRequest()
        request.sortDescriptors = [NSSortDescriptor(key: "createdAt", ascending: true)]
        let households = (try? context.fetch(request)) ?? []
        guard let adopted = households.first(where: { $0 != current }) else { return false }

        // Only abandon our own household if nothing was added to it in the
        // meantime; a user who added items before the first import finished
        // keeps them rather than having them stranded.
        guard itemCount(for: current, in: context) == 0 else { return false }

        activate(adopted)
        context.delete(current)
        try? context.save()
        stopObservingForAdoption()
        return true
    }

    private func itemCount(for household: Household, in context: NSManagedObjectContext) -> Int {
        let request = GroceryItem.fetchRequest()
        request.predicate = NSPredicate(format: "household == %@", household)
        return (try? context.count(for: request)) ?? 0
    }

    private func observeForAdoption() {
        guard !inMemory, activeHouseholdWasAutoCreated, householdAdoptionObserver == nil else { return }
        householdAdoptionObserver = NotificationCenter.default.addObserver(
            forName: .NSPersistentStoreRemoteChange, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.adoptSyncedHouseholdIfPresent() }
        }
    }

    private func stopObservingForAdoption() {
        if let householdAdoptionObserver {
            NotificationCenter.default.removeObserver(householdAdoptionObserver)
            self.householdAdoptionObserver = nil
        }
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
        activeHouseholdWasAutoCreated = true
        persistAutoCreatedFlag()
        persistActiveHouseholdID(household)
        return household
    }

    private func persistActiveHouseholdID(_ household: Household) {
        guard !inMemory else { return }
        UserDefaults.standard.set(household.id?.uuidString, forKey: Self.activeHouseholdIDKey)
    }

    /// The provisional flag has to survive relaunches: the first import can
    /// easily land after the app has been quit and reopened.
    private func persistAutoCreatedFlag() {
        guard !inMemory else { return }
        UserDefaults.standard.set(activeHouseholdWasAutoCreated, forKey: Self.autoCreatedKey)
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
