import Foundation

struct AlertState: Identifiable {
    let id = UUID()
    let title: String
    let message: String
}
