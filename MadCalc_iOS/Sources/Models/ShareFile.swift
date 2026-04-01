import Foundation

struct ShareFile: Identifiable, Sendable {
    let id = UUID()
    let url: URL
}
