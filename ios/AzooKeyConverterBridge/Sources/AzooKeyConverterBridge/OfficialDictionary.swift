import Foundation
import ZIPFoundation

/// Download on an actor, then publish a complete immutable snapshot atomically.
public actor OfficialDictionary {
    public static let shared = OfficialDictionary()
    private var updating = false

    public static func cachedURL(in container: URL) -> URL? {
        let cache = container.appendingPathComponent("official_dictionary", isDirectory: true)
        guard let sha = try? String(contentsOf: cache.appendingPathComponent("current"), encoding: .utf8),
              validSHA(sha) else { return nil }
        let root = cache.appendingPathComponent("\(sha)/Dictionary", isDirectory: true)
        return FileManager.default.fileExists(atPath: root.appendingPathComponent("louds/charID.chid").path)
            ? root : nil
    }

    private static func validSHA(_ sha: String) -> Bool {
        sha.count == 40 && sha.utf8.allSatisfy { (48...57).contains($0) || (97...102).contains($0) }
    }

    public func refreshIfDue(in container: URL) async throws {
        guard !updating else { return }
        updating = true
        defer { updating = false }
        let fm = FileManager.default
        let cache = container.appendingPathComponent("official_dictionary", isDirectory: true)
        try fm.createDirectory(at: cache, withIntermediateDirectories: true)
        func recent(_ name: String, seconds: TimeInterval) -> Bool {
            let attributes = try? fm.attributesOfItem(atPath: cache.appendingPathComponent(name).path)
            guard let modified = attributes?[.modificationDate] as? Date else { return false }
            return Date().timeIntervalSince(modified) < seconds
        }
        guard !recent("checked", seconds: 86400), !recent("attempt", seconds: 3600) else { return }
        try Data().write(to: cache.appendingPathComponent("attempt"), options: .atomic)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 60
        configuration.timeoutIntervalForResource = 300
        configuration.httpAdditionalHeaders = ["User-Agent": "Keynako-dictionary"]
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        let api = URL(string: "https://api.github.com/repos/azooKey/azooKey_dictionary_storage/commits/main")!
        let (metadata, response) = try await session.data(from: api)
        guard (response as? HTTPURLResponse)?.statusCode == 200,
              let object = try JSONSerialization.jsonObject(with: metadata) as? [String: Any],
              let sha = object["sha"] as? String, Self.validSHA(sha) else { throw URLError(.badServerResponse) }
        if Self.cachedURL(in: container)?.deletingLastPathComponent().lastPathComponent != sha {
            let url = URL(string: "https://codeload.github.com/azooKey/azooKey_dictionary_storage/zip/\(sha)")!
            let (download, archiveResponse) = try await session.download(from: url)
            defer { try? fm.removeItem(at: download) }
            guard (archiveResponse as? HTTPURLResponse)?.statusCode == 200,
                  (try fm.attributesOfItem(atPath: download.path)[.size] as? NSNumber)?.intValue ?? Int.max <= 128 * 1024 * 1024
            else { throw URLError(.badServerResponse) }
            let archive = try Archive(url: download, accessMode: .read)
            let staging = cache.appendingPathComponent("staging-\(UUID().uuidString)", isDirectory: true)
            try fm.createDirectory(at: staging, withIntermediateDirectories: true)
            defer { try? fm.removeItem(at: staging) }
            let prefix = "azooKey_dictionary_storage-\(sha)/"
            var total: UInt64 = 0
            var count = 0
            for entry in archive {
                count += 1
                total += UInt64(entry.uncompressedSize)
                guard count <= 5000, total <= 256 * 1024 * 1024,
                      entry.path.hasPrefix(prefix), entry.type != .symlink else { throw URLError(.cannotDecodeContentData) }
                let relative = String(entry.path.dropFirst(prefix.count))
                guard !relative.hasPrefix("/"), !relative.contains("\\"),
                      !relative.split(separator: "/").contains(where: { $0 == ".." || $0 == "." })
                else { throw URLError(.cannotDecodeContentData) }
                guard entry.type == .file, relative.hasPrefix("Dictionary/") || relative == "LICENSE" else { continue }
                let target = staging.appendingPathComponent(relative)
                try fm.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
                guard try archive.extract(entry, to: target) == entry.checksum
                else { throw URLError(.cannotDecodeContentData) }
            }
            try Self.validate(staging)
            let destination = cache.appendingPathComponent(sha, isDirectory: true)
            if !fm.fileExists(atPath: destination.path) { try fm.moveItem(at: staging, to: destination) }
            try Data(sha.utf8).write(to: cache.appendingPathComponent("current"), options: .atomic)
        }
        try Data(sha.utf8).write(to: cache.appendingPathComponent("checked"), options: .atomic)
    }

    static func validate(_ repo: URL) throws {
        let fm = FileManager.default
        let root = repo.appendingPathComponent("Dictionary", isDirectory: true)
        func size(_ name: String) throws -> Int {
            (try fm.attributesOfItem(atPath: root.appendingPathComponent(name).path)[.size] as? NSNumber)?.intValue ?? 0
        }
        guard try String(contentsOf: repo.appendingPathComponent("LICENSE"), encoding: .utf8).contains("Apache License"),
              try size("louds/charID.chid") > 0, try size("mm.binary") >= 1_008_020 else { throw URLError(.cannotDecodeContentData) }
        let characters = try String(contentsOf: root.appendingPathComponent("louds/charID.chid"), encoding: .utf8).unicodeScalars
        guard characters.count <= 256, Set(characters).count == characters.count else { throw URLError(.cannotDecodeContentData) }
        for cid in 0..<1319 {
            let length = try size("cb/\(cid).binary")
            guard length > 0, length % 8 == 0 else { throw URLError(.cannotDecodeContentData) }
        }
        let shards = try fm.contentsOfDirectory(atPath: root.appendingPathComponent("louds").path).filter { $0.hasSuffix(".louds") }
        guard !shards.isEmpty else { throw URLError(.cannotDecodeContentData) }
        for shard in shards {
            let stem = String(shard.dropLast(6))
            let length = try size("louds/\(shard)")
            guard length > 0, length % 8 == 0,
                  try size("louds/\(stem).loudschars2") > 0,
                  try size("louds/\(stem)0.loudstxt3") > 0 else { throw URLError(.cannotDecodeContentData) }
        }
    }
}
