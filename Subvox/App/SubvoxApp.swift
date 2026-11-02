import SwiftUI

@main
struct SubvoxApp: App {
    @StateObject private var model = AppModel()

    var body: some Scene {
        WindowGroup("Subvox") {
            ContentView()
                .environmentObject(model)
                .frame(minWidth: 980, minHeight: 680)
                .onAppear { model.start() }
        }
    }
}
