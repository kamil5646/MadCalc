import Foundation

struct AlertState: Identifiable, Sendable {
    let id = UUID()
    let title: String
    let message: String
}
