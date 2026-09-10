import SwiftUI
import CoreData

@main
struct XWasteWatchApp: App {
    @StateObject private var persistence = LaunchSupport.makePersistenceController()

    var body: some Scene {
        WindowGroup {
            WatchRootView(persistence: persistence)
                .environment(\.managedObjectContext, persistence.container.viewContext)
        }
    }
}
