// SPDX-License-Identifier: AGPL-3.0-or-later
import UIKit
import ZIPFoundation

/// Generated archives live only in this app's cache, never in Realm or iCloud.
final class AdaptiveSkinStore {
    static let shared = AdaptiveSkinStore()
    private var results: [String: URL] = [:]
    func skin(console: AdaptiveGameSystem, sourceURL: URL, size: CGSize, safeArea: UIEdgeInsets) throws -> URL {
        let values = [size.width, size.height, safeArea.top, safeArea.left, safeArea.bottom, safeArea.right]
        let key = console.rawValue + "-" + values.map { String(Int(($0 * 100).rounded())) }.joined(separator: "-")
        if let result = results[key], FileManager.default.fileExists(atPath: result.path) { return result }
        let directory = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("AdaptiveSkins-v1", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent(key + ".manicskin")
        let archive = try Archive(url: sourceURL, accessMode: .read)
        guard let infoEntry = archive["info.json"] else { throw AdaptiveSkinDefinition.Failure.invalidSource }
        func data(_ entry: Entry) throws -> Data {
            var result = Data()
            _ = try archive.extract(entry) { result.append($0) }
            return result
        }
        let payload = try AdaptiveSkinDefinition.make(source: data(infoEntry), console: console, size: size,
            safeArea: safeArea, key: key, asset: { name in
                guard let entry = archive[name] else { return nil }
                return try? data(entry)
            })
        let temporary = directory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: temporary, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: temporary) }
        try FileManager.default.unzipItem(at: sourceURL, to: temporary)
        try payload.info.write(to: temporary.appendingPathComponent("info.json"), options: .atomic)
        for (name, bytes) in payload.files { try bytes.write(to: temporary.appendingPathComponent(name), options: .atomic) }
        // This path belongs exclusively to our generated cache, not user skins.
        if FileManager.default.fileExists(atPath: url.path) { try FileManager.default.removeItem(at: url) }
        try FileManager.default.zipItem(at: temporary, to: url, shouldKeepParent: false)
        results[key] = url
        return url
    }
}
