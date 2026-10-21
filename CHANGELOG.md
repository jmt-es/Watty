# Changelog

All notable changes to Watty are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [1.3.0] - 2026-10-21

The first public release. The lists below describe what is new compared with the private builds that came before it.

### Added

- A settings window: choose what the menu bar shows (percentage, time remaining, power in watts or icon only), turn on notifications for low battery, a charge limit reminder and a full battery, and launch Watty at login.
- Battery history that persists across restarts, charted for the last 1, 6 or 24 hours with the charging periods shaded.
- Support for desktop Macs: a Mac without a battery hides the battery sections and shows the CPU usage in the menu bar, and keeps CPU, memory, temperature, per-app energy and the energy mode.
- The `watty` command line tool (`status`, `status --json`, `top`, `watch` and `show`), built from the same library as the app and embedded in `Watty.app`.
- Spanish localization next to English, and VoiceOver labels for the menu bar item, the battery level, the charts, the power flow and the app list.
- Homebrew installation with `brew install jmt-es/tap/watty`, including a `brew services` service that starts the app at login and restarts it after a crash.
- A universal (Apple Silicon and Intel) zip on GitHub Releases, signed ad hoc, with a SHA-256 checksum file.
- `make install`, `make uninstall` and `make release`, with scripts in `scripts/` that work with the Xcode Command Line Tools alone.
- Launch arguments that render the panel or the settings window to a PNG (`--capture-panel`, `--capture-settings`, `--appearance` and `--history-file`), and `--demo` with `--demo-scenario` to render sample data instead of the real readings, for the screenshots in the documentation.
- GitHub Actions workflows that build and test every change and publish releases.
- An MIT license, documentation, a contribution guide and a security policy.

### Changed

- Battery and system telemetry is read in-process through IOKit instead of parsing the output of command line tools. `ioreg` remains only as a fallback.
- Refreshes while the panel is closed use a cheap snapshot that starts no processes.
- Temperature sensors are looked up once, and a Mac that has none is checked again every 5 minutes instead of on every sample.
- App names come from the app bundle, so the hand-written name rewrites for individual apps are gone. Each per-app sample keeps the 25 busiest apps.
- Settings, battery settings, About and Quit share one menu in the panel header.
- Screenshots are captured with launch arguments instead of a URL, so no URL can make Watty write a file. A `watty://` URL only opens the panel.
- Installing from source builds with the Command Line Tools, runs the tests only on request and starts at login only with `LAUNCH_AGENT=1`; the LaunchAgent is generated from the real install path.
- The version shown in the app, the app bundle and the scripts all come from `WattyVersion.swift`.

## [Earlier private versions]

Versions 1.1.0 to 1.2.1 were private builds from September 2026 and were never released.

They introduced the IOKit power readings with immediate updates when the charger is plugged or unplugged, Low Power Mode changes and wake, the adaptive refresh and its freshness indicator, the energy mode control, the per-app energy list grouped by app bundle, the Activity charts with the SoC temperature, the power flow view, the collapsible health section, and the memory footprint that replaced the unreliable billed energy counter in the app list. All of it is part of 1.3.0.

[Unreleased]: https://github.com/jmt-es/Watty/compare/v1.3.0...HEAD
[1.3.0]: https://github.com/jmt-es/Watty/releases/tag/v1.3.0
