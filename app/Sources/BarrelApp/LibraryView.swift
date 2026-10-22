import AppKit
import BarrelAppKit
import BarrelCore
import SwiftUI

/// The Steam home: install Steam, then play the games it has installed.
struct LibraryView: View {
    let steamBottle: String?
    let games: [GameSummary]
    let isBusy: Bool
    let isAvailable: (GraphicsBackend) -> Bool
    let actions: Actions

    struct Actions {
        var installSteam: () -> Void
        var openSteam: () -> Void
        var refresh: () -> Void
        var play: (GameSummary) -> Void
        var setGraphics: (GameSummary, GraphicsBackend) -> Void
        var setAutomaticGraphics: (GameSummary) -> Void
        var addToDock: (GameSummary) -> Void
    }

    var body: some View {
        Group {
            if steamBottle == nil {
                Welcome(isBusy: isBusy, install: actions.installSteam)
            } else if games.isEmpty {
                ContentUnavailableView {
                    Label("No games yet", systemImage: "gamecontroller")
                } description: {
                    Text("Open Steam, sign in and install a Windows game. It shows up here when it finishes.")
                } actions: {
                    Button("Open Steam", action: actions.openSteam).buttonStyle(.borderedProminent)
                    Button("Refresh", action: actions.refresh)
                }
            } else {
                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 300), spacing: 16)], spacing: 16) {
                        ForEach(games) { game in
                            GameCard(game: game, isAvailable: isAvailable, isBusy: isBusy,
                                     play: { actions.play(game) },
                                     setGraphics: { actions.setGraphics(game, $0) },
                                     setAutomatic: { actions.setAutomaticGraphics(game) },
                                     addToDock: { actions.addToDock(game) })
                        }
                    }
                    .padding(20)
                }
            }
        }
        .navigationTitle("Library")
        .toolbar {
            if steamBottle != nil {
                ToolbarItem {
                    Button(action: actions.refresh) { Label("Refresh", systemImage: "arrow.clockwise") }
                        .help("Look for newly installed games")
                }
                ToolbarItem {
                    Button(action: actions.openSteam) { Label("Open Steam", systemImage: "cloud") }
                        .help("Open Steam to sign in, buy or install games")
                }
            }
        }
    }
}

/// First run: one button that installs Steam into its own bottle.
private struct Welcome: View {
    let isBusy: Bool
    let install: () -> Void

    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: "gamecontroller.fill")
                .font(.system(size: 54))
                .foregroundStyle(.tint)
            Text("Play your Windows games")
                .font(.largeTitle.weight(.bold))
            Text("Barrel installs the Windows version of Steam and sets it up for you. Sign in, install your games, and play them from here or from the Dock.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .frame(maxWidth: 440)
            Button(action: install) {
                Text("Install Steam").padding(.horizontal, 12)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(isBusy)
            Text("Takes about a minute. Steam updates itself the first time it opens.")
                .font(.footnote)
                .foregroundStyle(.tertiary)
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct GameCard: View {
    let game: GameSummary
    let isAvailable: (GraphicsBackend) -> Bool
    let isBusy: Bool
    let play: () -> Void
    let setGraphics: (GraphicsBackend) -> Void
    let setAutomatic: () -> Void
    let addToDock: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 14) {
                GameIcon(executablePath: game.executablePath)
                VStack(alignment: .leading, spacing: 4) {
                    Text(game.name).font(.headline).lineLimit(2)
                    StatusBadge(status: game.profileStatus)
                }
                Spacer(minLength: 0)
            }
            LabeledContent("Graphics") {
                Menu {
                    Button {
                        setAutomatic()
                    } label: {
                        if game.graphics.source == .player { Text("Automatic") } else { Label("Automatic", systemImage: "checkmark") }
                    }
                    .help("Use the game's tested profile, or Steam's default")
                    Divider()
                    ForEach([GraphicsBackend.dxvk, .dxmt, .wined3d], id: \.self) { backend in
                        Button {
                            setGraphics(backend)
                        } label: {
                            if game.graphics.source == .player && backend == game.graphics.backend {
                                Label(backend.displayName, systemImage: "checkmark")
                            } else {
                                Text(backend.displayName)
                            }
                        }
                        .disabled(!isAvailable(backend))
                    }
                } label: {
                    Text(game.graphics.source == .player ? game.graphics.backend.displayName
                                                         : "Automatic · \(game.graphics.backend.displayName)")
                }
                .fixedSize()
                .disabled(!game.canChooseGraphics || isBusy)
                .help(game.canChooseGraphics ? game.graphics.source.explanation
                                             : "Barrel could not tell which file is the game, so it uses the default")
            }
            HStack {
                Button(action: play) { Label("Play", systemImage: "play.fill").frame(maxWidth: .infinity) }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                Button(action: addToDock) { Label("Add to Dock", systemImage: "dock.rectangle") }
                    .controlSize(.large)
                    .help("Create a Mac app for this game in ~/Applications/Barrel")
            }
            .disabled(isBusy)
        }
        .padding(16)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 14))
    }
}

private struct StatusBadge: View {
    let status: GameStatus?

    var body: some View {
        switch status {
        case .works: badge("Tested: works", "checkmark.seal.fill", .green)
        case .issues: badge("Tested: known issues", "exclamationmark.triangle.fill", .orange)
        case .broken: badge("Tested: not working", "xmark.octagon.fill", .red)
        case nil: badge("Default settings", "gearshape", .secondary)
        }
    }

    private func badge(_ text: String, _ symbol: String, _ color: Color) -> some View {
        Label(text, systemImage: symbol).font(.caption).foregroundStyle(color)
    }
}

/// The icon inside the game's Windows executable, loaded off the main thread.
private struct GameIcon: View {
    let executablePath: String?
    @State private var image: NSImage?

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image).resizable().interpolation(.high)
            } else {
                Image(systemName: "gamecontroller.fill").font(.system(size: 26)).foregroundStyle(.secondary)
            }
        }
        .frame(width: 48, height: 48)
        .task(id: executablePath) {
            guard let path = executablePath else { return }
            let data = await Task.detached(priority: .utility) {
                (try? Data(contentsOf: URL(fileURLWithPath: path), options: .alwaysMapped))
                    .flatMap { try? PEIcon.largestIcon(in: $0) }
            }.value
            image = data.flatMap(NSImage.init(data:))
        }
    }
}

extension GraphicsBackend {
    var displayName: String {
        switch self {
        case .dxvk: "DXVK"
        case .dxmt: "DXMT"
        case .wined3d: "wined3d (OpenGL)"
        case .d3dmetal: "D3DMetal"
        }
    }
}

extension GraphicsSource {
    var explanation: String {
        switch self {
        case .player: "You chose this for the game"
        case .profile: "From the game's tested profile"
        case .bottle: "Steam's default"
        }
    }
}
