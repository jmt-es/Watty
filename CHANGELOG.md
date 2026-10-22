# Changelog

All notable changes to Watty are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [1.3.1] - 2026-10-22

### Fixed

- A charger that cannot keep up with the Mac is no longer reported as charging. macOS keeps saying `Charging`, with an estimate of hours to full, while the battery falls, and Watty used to repeat it. Watty now judges what the battery is really doing from its average power over the last minutes and the trend of its level.
- While the Mac is plugged in and the battery is losing charge, the status says `Plugged in, draining` in orange, the line under the level says `The 20 W adapter can't keep up` instead of the time to full (or `Using the battery while plugged in` when macOS itself is not charging, as with a charge limiter that discharges on purpose), the header icon, the ring and the menu bar icon get a warning symbol instead of the bolt, VoiceOver says `Battery 18%, plugged in, draining`, the power flow shows the averaged battery power as draining, and the history chart shades those periods in orange instead of green.
- The charge limit and fully charged reminders no longer treat a battery that is draining on the charger as charging or full.
- The system load that Watty derives when the battery controller does not report it now adds what the battery gives while it supplements the adapter.

### Added

- `battery.net_flow` in `watty status --json`: `charging`, `draining`, `holding` or `null`, next to the `state` that macOS reports. While it is `draining` on the charger, `battery.time_to_full_minutes` is `null`.
- `watty status` says `Plugged in, draining` and names the adapter that cannot keep up. It judges from its single reading, and the documentation says what that limits.
- `watty watch` judges the net flow over the samples it takes, on the live screen and in a new `net_flow=` field at the end of each piped line.
- A `draining` demo scenario (`--demo --demo-scenario draining`) that renders a 20 W charger losing about 18 W to the load, with a history that falls while plugged in.
- The average battery power is read from the power accumulators of the battery controller, checked against the battery gauge's own current counter on the Mac Watty is developed on. See [how it works](docs/how-it-works.md#is-the-battery-really-charging).

### Changed

- The piped lines of `watty watch` carry a sixth field, `net_flow`, after `system_w`.

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

[Unreleased]: https://github.com/jmt-es/Watty/compare/v1.3.1...HEAD
[1.3.1]: https://github.com/jmt-es/Watty/compare/v1.3.0...v1.3.1
[1.3.0]: https://github.com/jmt-es/Watty/releases/tag/v1.3.0
