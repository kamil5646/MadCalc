import SwiftUI

@main
struct MadCalcApp: App {
    @StateObject private var viewModel = MadCalcViewModel()

    var body: some Scene {
        WindowGroup {
            ContentView(viewModel: viewModel)
        }
    }
}
