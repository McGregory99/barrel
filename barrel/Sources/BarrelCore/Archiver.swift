import Foundation

/// Port for packing a bottle directory into a single archive file and back.
public protocol Archiver {
    func archive(directory: URL, to archive: URL) throws
    func extract(_ archive: URL, into directory: URL) throws
}

/// gzip-compressed tar via the system `tar`, rooted at the bottle directory name.
public struct TarArchiver: Archiver {
    public init() {}

    public func archive(directory: URL, to archive: URL) throws {
        try tar(["-czf", archive.path, "-C", directory.deletingLastPathComponent().path,
                 directory.lastPathComponent])
    }

    public func extract(_ archive: URL, into directory: URL) throws {
        try tar(["-xzf", archive.path, "-C", directory.path])
    }

    private func tar(_ arguments: [String]) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/tar")
        process.arguments = arguments
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw WineRuntimeError.commandFailed(command: "tar " + arguments.joined(separator: " "),
                                                 status: process.terminationStatus)
        }
    }
}
