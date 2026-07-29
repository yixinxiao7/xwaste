import SwiftUI
import CoreData
import CloudKit
#if os(iOS)
import UIKit
#endif

@main
struct XWasteApp: App {
    #if os(iOS)
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    #endif

    @StateObject private var persistence = PersistenceController.shared

    init() {
        #if DEBUG
        // Opt-in CloudKit development schema push (task 3.4): run once with
        // PUSH_CK_SCHEMA=1 in the scheme environment after signing is set up.
        if ProcessInfo.processInfo.environment["PUSH_CK_SCHEMA"] == "1" {
            PersistenceController.shared.pushCloudKitDevelopmentSchema()
        }
        #endif
    }

    var body: some Scene {
        WindowGroup {
            RootTabView(persistence: persistence)
                .environment(\.managedObjectContext, persistence.container.viewContext)
        }
    }
}

struct RootTabView: View {
    @ObservedObject var persistence: PersistenceController

    var body: some View {
        let household = persistence.activeHousehold!
        TabView {
            NavigationStack { ShoppingListView(household: household) }
                .tabItem { Label("Shopping List", systemImage: "cart") }
            NavigationStack { HomeInventoryView(household: household) }
                .tabItem { Label("At Home", systemImage: "house") }
        }
        // Joining or leaving a household swaps every fetch to the new scope.
        .id(household.objectID)
    }
}

#if os(iOS)
/// SwiftUI has no native hook for CloudKit share acceptance, so a minimal app
/// delegate routes it in. Scene-based apps get the callback on the *scene*
/// delegate, which the app delegate has to install; the app-level variant is
/// kept as a fallback for pre-scene delivery paths.
final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication,
                     configurationForConnecting connectingSceneSession: UISceneSession,
                     options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        let configuration = UISceneConfiguration(name: nil, sessionRole: connectingSceneSession.role)
        configuration.delegateClass = SceneDelegate.self
        return configuration
    }

    func application(_ application: UIApplication,
                     userDidAcceptCloudKitShareWith cloudKitShareMetadata: CKShare.Metadata) {
        PersistenceController.shared.acceptShareInvitation(cloudKitShareMetadata)
    }
}

final class SceneDelegate: NSObject, UIWindowSceneDelegate {
    func windowScene(_ windowScene: UIWindowScene,
                     userDidAcceptCloudKitShareWith cloudKitShareMetadata: CKShare.Metadata) {
        PersistenceController.shared.acceptShareInvitation(cloudKitShareMetadata)
    }
}
#endif

#Preview {
    RootTabView(persistence: PersistenceController.preview)
        .environment(\.managedObjectContext, PersistenceController.preview.container.viewContext)
}
