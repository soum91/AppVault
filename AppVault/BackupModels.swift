import Foundation

struct BackupItem: Identifiable, Codable, Hashable {
    var id: String { bundleIdentifier }
    let bundleIdentifier: String
    let containerPath: String
    let displayName: String
    let dataSize: Int64
}

struct BackupManifest: Codable {
    let formatVersion: Int
    let createdAt: Date
    let deviceName: String
    let systemVersion: String
    let bundleIdentifier: String
    let displayName: String
    let included: [String]
}

enum BackupError: LocalizedError {
    case accessUnavailable
    case noContainers
    case destinationUnavailable

    var errorDescription: String? {
        switch self {
        case .accessUnavailable: "worse_query access could not be opened for this container."
        case .noContainers: "No readable app containers were found."
        case .destinationUnavailable: "Could not create the backup archive."
        }
    }
}
