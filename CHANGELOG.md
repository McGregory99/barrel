# Changelog

What changed in Barrel, newest first. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and versions follow
[Semantic Versioning](https://semver.org/).

## [Unreleased]

### Added

- Barrel has its own icon in the Dock and in Finder.

### Fixed

- Games no longer freeze or slow to a crawl when they open the microphone, for example for
  voice chat. macOS was stopping the game because Barrel does not ask for microphone access
  yet, so games now see no microphone instead. Voice chat recording comes later.
- Game sound now follows the Mac's output device: switch to headphones or a display while
  playing and the sound moves with it.

## [0.1.0] - 2026-10-22

First public beta.

### Added

- Steam first: Barrel installs the Windows version of Steam with the fixes it needs on a Mac,
  and lists the games you install.
- Play each game with the right graphics engine: DXVK, DXMT or wined3d, chosen by the game's
  tested profile or by you. **Automatic** follows the profile.
- Game profiles (`profiles/`) and `barrel games`, `barrel play` and `barrel launcher game`.
- Add to Dock: each game can become a Mac app with its own icon.
- Bottles, recipes and the `barrel` command line for advanced use.
- `Barrel.app` with a self-contained Wine 11 runtime (CrossOver 26.3's open-source patches),
  DXVK, DXMT, MoltenVK and GStreamer.
- Game report form and GitHub Discussions for feedback.

[Unreleased]: https://github.com/McGregory99/barrel/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/McGregory99/barrel/releases/tag/v0.1.0
