import CryptoKit
import Foundation

/// Port: fetches a URL into a local file.
public protocol Downloader {
    func download(from url: URL, to destination: URL) throws
}

public enum SHA256Hasher {
    public static func hex(of data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    public static func hex(ofFileAt url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hasher = SHA256()
        while let chunk = try handle.read(upToCount: 1 << 20), !chunk.isEmpty { hasher.update(data: chunk) }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
}

/// Download cache under `$BARREL_HOME/Downloads`: a cached file whose hash matches is never fetched again.
public struct DownloadCache {
    public let directory: URL
    let downloader: Downloader

    public init(directory: URL, downloader: Downloader) {
        self.directory = directory
        self.downloader = downloader
    }

    public func localURL(for fileName: String) -> URL {
        directory.appendingPathComponent(fileName)
    }

    /// Returns the verified local file, downloading it when absent or corrupt.
    @discardableResult
    public func fetch(_ step: DownloadStep) throws -> URL {
        let fileManager = FileManager.default
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        let target = localURL(for: step.fileName)
        if fileManager.fileExists(atPath: target.path), (try? SHA256Hasher.hex(ofFileAt: target)) == step.sha256 {
            return target
        }

        let partial = directory.appendingPathComponent(".\(step.fileName).\(UUID().uuidString).part")
        defer { try? fileManager.removeItem(at: partial) }
        try downloader.download(from: step.url, to: partial)
        let actual = try SHA256Hasher.hex(ofFileAt: partial)
        guard actual == step.sha256 else {
            throw RecipeError.hashMismatch(file: step.fileName, expected: step.sha256, actual: actual)
        }
        if fileManager.fileExists(atPath: target.path) { try fileManager.removeItem(at: target) }
        try fileManager.moveItem(at: partial, to: target)
        return target
    }
}

/// Real downloader over URLSession (blocking).
public struct URLSessionDownloader: Downloader {
    public init() {}

    private final class Outcome: @unchecked Sendable {
        var location: URL?
        var error: Error?
    }

    public func download(from url: URL, to destination: URL) throws {
        let outcome = Outcome()
        let semaphore = DispatchSemaphore(value: 0)
        let task = URLSession.shared.downloadTask(with: url) { location, response, error in
            if let error {
                outcome.error = error
            } else if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                outcome.error = RecipeError.downloadFailed(url: url.absoluteString, reason: "HTTP \(http.statusCode)")
            } else if let location {
                // The temporary file is deleted when this handler returns, so move it now.
                do {
                    try? FileManager.default.removeItem(at: destination)
                    try FileManager.default.moveItem(at: location, to: destination)
                    outcome.location = destination
                } catch { outcome.error = error }
            }
            semaphore.signal()
        }
        task.resume()
        semaphore.wait()
        if let error = outcome.error {
            if let recipeError = error as? RecipeError { throw recipeError }
            throw RecipeError.downloadFailed(url: url.absoluteString, reason: error.localizedDescription)
        }
        guard outcome.location != nil else {
            throw RecipeError.downloadFailed(url: url.absoluteString, reason: "no data received")
        }
    }
}
