import SwiftUI

@main
struct SoccerStrikerMacApp: App {
    @State private var server = NetworkServer()

    var body: some Scene {
        WindowGroup {
            RootView(server: server)
        }
        .windowResizability(.contentSize)
    }
}
