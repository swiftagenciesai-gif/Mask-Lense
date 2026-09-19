import SwiftUI

@main
struct MaskLensApp: App {
    @StateObject private var maskConnection = MaskConnectionManager()
    @StateObject private var appSettings = AppSettings()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(maskConnection)
                .environmentObject(appSettings)
        }
    }
}
