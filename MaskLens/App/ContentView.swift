import SwiftUI

struct ContentView: View {
    var body: some View {
        TabView {
            NavigationStack {
                StagesHomeView()
            }
            .tabItem { Label("Stages", systemImage: "list.number") }

            NavigationStack {
                SettingsView()
            }
            .tabItem { Label("Settings", systemImage: "gear") }
        }
    }
}
