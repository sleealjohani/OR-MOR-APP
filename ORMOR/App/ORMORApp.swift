import SwiftUI

@main
struct ORMORApp: App {
    @StateObject private var settings = AppSettings()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(settings)
                .preferredColorScheme(.light)
                .tint(Brand.gold)
        }
    }
}
