import SwiftUI
import CoreData

/// Two vertical pages, list first — the phone's two destinations without any
/// watch navigation chrome. Above them sits the account gate: with no reachable
/// iCloud account there is nothing honest to show, because the watch has no
/// local-only mode.
struct WatchRootView: View {
    @ObservedObject var persistence: PersistenceController
    @StateObject private var account: WatchAccountMonitor

    init(persistence: PersistenceController) {
        self.persistence = persistence
        let context = persistence.container.viewContext
        _account = StateObject(wrappedValue: WatchAccountMonitor(
            container: persistence.container,
            hasLocalData: WatchAccountMonitor.hasLocalData(in: context)
        ))
    }

    var body: some View {
        let household = persistence.activeHousehold!
        Group {
            switch account.availability {
            case .checking:
                ProgressView()
                    .accessibilityIdentifier("account-checking")
            case .unavailable:
                RequiresICloudView()
            case .available:
                TabView {
                    NavigationStack {
                        WatchListView(household: household, location: .shoppingList,
                                      isPerformingFirstImport: account.isPerformingFirstImport)
                    }
                    NavigationStack {
                        WatchListView(household: household, location: .atHome,
                                      isPerformingFirstImport: account.isPerformingFirstImport)
                    }
                }
                .tabViewStyle(.verticalPage)
            }
        }
        // Joining or leaving a household swaps every fetch to the new scope.
        .id(household.objectID)
    }
}

/// The app's identity ceiling, stated plainly rather than as an empty list.
struct RequiresICloudView: View {
    var body: some View {
        EmptyStateView(systemImage: "icloud.slash",
                       title: "iCloud Required",
                       message: "Sign in to iCloud on this watch to see your household's list. Adding and editing items stays on your iPhone.")
            .accessibilityIdentifier("requires-icloud")
    }
}
