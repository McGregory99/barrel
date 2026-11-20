import CoreGraphics
import Foundation

/// One on-screen window as the window server reports it. Titles are left out: reading them
/// needs Screen Recording permission.
public struct ScreenWindow: Equatable, Sendable {
    public var id: Int
    public var ownerName: String
    public var ownerPID: Int32
    public var layer: Int
    public var width: Double
    public var height: Double

    public init(id: Int, ownerName: String, ownerPID: Int32, layer: Int, width: Double, height: Double) {
        self.id = id
        self.ownerName = ownerName
        self.ownerPID = ownerPID
        self.layer = layer
        self.width = width
        self.height = height
    }
}

/// Port for the windows currently on screen.
public protocol WindowSource: Sendable {
    func onScreenWindows() -> [ScreenWindow]
}

/// Reads the on-screen window list from the window server.
public struct SystemWindowSource: WindowSource {
    public init() {}

    public func onScreenWindows() -> [ScreenWindow] {
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let info = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else { return [] }
        return info.compactMap { window in
            guard let id = window[kCGWindowNumber as String] as? Int,
                  let bounds = window[kCGWindowBounds as String] as? [String: Any],
                  let rect = CGRect(dictionaryRepresentation: bounds as CFDictionary) else { return nil }
            return ScreenWindow(id: id, ownerName: window[kCGWindowOwnerName as String] as? String ?? "",
                                ownerPID: window[kCGWindowOwnerPID as String] as? Int32 ?? 0,
                                layer: window[kCGWindowLayer as String] as? Int ?? 0,
                                width: rect.width, height: rect.height)
        }
    }
}

/// Decides when Steam's window is on screen after Open Steam. Under Wine, Steam's window can
/// take most of a minute to appear; Wine also keeps small helper windows around, so only a new,
/// normal-level, large window owned by Wine counts.
public struct SteamWindowWatch: Sendable {
    public enum Launch: Equatable, Sendable {
        case running
        case exited(Int32)
    }

    public enum State: Equatable, Sendable {
        case waiting
        case ready
        case failed(exitCode: Int32)
        case timedOut
    }

    /// Steam's main window is about 1280x800; Wine's helper windows are 500x500.
    static let minimumWidth: Double = 600

    private let before: Set<Int>
    private let startedAt: Date
    private let timeout: TimeInterval

    public init(before: [ScreenWindow], startedAt: Date, timeout: TimeInterval = 180) {
        self.before = Set(before.filter(Self.looksLikeSteam).map(\.id))
        self.startedAt = startedAt
        self.timeout = timeout
    }

    public func state(windows: [ScreenWindow], now: Date, launch: Launch) -> State {
        let candidates = windows.filter(Self.looksLikeSteam)
        if candidates.contains(where: { !before.contains($0.id) }) { return .ready }
        switch launch {
        case .exited(let code) where code != 0:
            return .failed(exitCode: code)
        case .exited:
            // A second steam.exe hands the request to the Steam already running and exits.
            if !candidates.isEmpty { return .ready }
        case .running:
            break
        }
        return now.timeIntervalSince(startedAt) >= timeout ? .timedOut : .waiting
    }

    static func looksLikeSteam(_ window: ScreenWindow) -> Bool {
        window.layer == 0 && window.ownerName.lowercased().hasPrefix("wine") && window.width >= minimumWidth
    }
}
