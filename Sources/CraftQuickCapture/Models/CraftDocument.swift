import Foundation

// MARK: - CraftDocument

struct CraftDocument: Identifiable, Hashable, Codable {
    let id: String
    let title: String
    let folderName: String?
    let spaceId: String?
    /// `true` = real Craft document ID (from craftdocs:// URL or metadata)
    /// `false` = synthetic UUID — write will target by title only
    let hasValidId: Bool
}

// MARK: - DocumentCache

/// Persists the document list to disk with a 15-minute TTL.
/// Stored at ~/Library/Application Support/CraftQuickCapture/documents-cache.json
struct DocumentCache: Codable {

    var documents: [CraftDocument]
    var lastUpdated: Date

    var isStale: Bool {
        Date().timeIntervalSince(lastUpdated) > 15 * 60
    }

    // MARK: Persistence

    static func load() -> DocumentCache? {
        guard let data = try? Data(contentsOf: cacheURL) else { return nil }
        return try? JSONDecoder().decode(DocumentCache.self, from: data)
    }

    func save() {
        let dir = Self.cacheURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        if let data = try? JSONEncoder().encode(self) {
            try? data.write(to: Self.cacheURL, options: .atomic)
        }
    }

    private static var cacheURL: URL {
        FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("CraftQuickCapture/documents-cache.json")
    }
}
