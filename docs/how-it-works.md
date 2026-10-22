# How Watty works

Watty reads power and activity data that macOS already exposes to normal users, shows it in a menu bar panel and, only when you ask, changes the energy mode. It has no background daemon, no privileged helper and no network access.

This page explains where each number comes from, how often it is read and where it stops being exact.

- [Structure](#structure)
- [Where the numbers come from](#where-the-numbers-come-from)
- [When it refreshes](#when-it-refreshes)
- [Battery and power flow](#battery-and-power-flow)
- [Is the battery really charging?](#is-the-battery-really-charging)
- [Energy by app](#energy-by-app)
- [Activity and temperature](#activity-and-temperature)
- [Battery health](#battery-health)
- [Energy mode](#energy-mode)
- [History and notifications](#history-and-notifications)
- [Desktop Macs](#desktop-macs)
- [What is stored and where](#what-is-stored-and-where)
- [Limits](#limits)
- [Logs and debugging](#logs-and-debugging)
- [What it does not do](#what-it-does-not-do)

## Structure

- `Sources/WattyCore` is the telemetry library: readers for the power sources and the battery, samplers for CPU, memory, temperature and per-app load, the parsers behind them, the estimator of the battery's net flow, the history store and the action that changes the energy mode.
- `Sources/Watty` is the SwiftUI app. A `MenuBarExtra` shows the panel from the menu bar, and the same view opens in a regular window when you ask for it.
- `Sources/WattyCLI` and `Sources/watty-cli` are the `watty` command. It uses the same library as the app, so the terminal and the panel agree. See the [command line reference](cli.md).

The app is an agent (`LSUIElement`): no Dock icon and no main menu bar of its own. Starting a second copy makes it exit, so only one instance runs. It has no third-party dependencies.

There are a few ways to bring up the panel: click the menu bar item, run `watty show`, open Watty again while it runs, or click one of its notifications. `watty show` talks to the running app through a local distributed notification. The app also registers the `watty://` URL scheme, but a `watty://` URL carries no commands and no paths: any of them just opens the panel.

## Where the numbers come from

| Value | Source |
| --- | --- |
| Charge level, charging state, time to full or empty, Low Power Mode | IOKit power sources (`IOPSCopyPowerSourcesInfo`) |
| Voltage, current, battery power, adapter input, system load, battery temperature | The `AppleSmartBattery` entry of the IOKit registry, read in-process |
| Net flow of the battery (charging, draining or holding) | The power accumulators in the `PowerTelemetryData` of the `AppleSmartBattery` entry, averaged over the last 150 seconds, and the trend of the charge level over the last 8 minutes. See [Is the battery really charging?](#is-the-battery-really-charging) |
| Cycle count, maximum capacity, condition, adapter rating | `system_profiler SPPowerDataType`, cached for 5 minutes, with the registry values as a fallback |
| Energy mode | `pmset -g` (the `powermode` key, or the older `lowpowermode` and `highpowermode` keys) |
| CPU load | `host_statistics` |
| Memory and swap | `host_statistics64` and the `vm.swapusage` sysctl |
| SoC temperature | The IOKit HID temperature sensors |
| Per-app CPU and memory | `proc_pid_rusage` for your own processes, `ps` for other users' processes |

Nothing needs administrator rights, and Watty never runs `powermetrics`. The only elevated action is the energy mode change you ask for.

The battery registry is read in-process through IOKit. Only when that read fails on a Mac that has a battery does Watty fall back to parsing the output of `ioreg`, and only for full snapshots. If no source produced a charge level at all, `pmset -g batt` is the last resort.

## When it refreshes

### Cadence

| | Panel open | Panel closed |
| --- | --- | --- |
| Battery and power snapshot | every 2 s | every 30 s |
| CPU, memory and temperature samples | with each snapshot | with each snapshot |
| Per-app list | about every 5 s | about once a minute |

The panel counts as open while the menu bar panel or the regular panel window is showing. While it is open a one-second clock keeps the "Updated N s ago" text current.

Some events refresh the snapshot immediately, whatever the panel is doing:

- launch, opening the panel and the refresh button in the panel header;
- a change reported by the IOKit power source notifications, such as plugging or unplugging the charger;
- a change of Low Power Mode, and waking the Mac or its display from sleep;
- the end of an energy mode change.

Power events arriving within 0.4 s of each other trigger a single refresh.

### Cheap and full snapshots

A snapshot comes in two depths, so that a closed panel costs almost nothing:

| | Cheap | Full |
| --- | --- | --- |
| Charge level, state, time estimates | IOKit power sources | the same |
| Voltage, current, power, temperature | `AppleSmartBattery` registry, in-process | the same, with the `ioreg` fallback |
| Energy mode | the last `pmset -g` result | `pmset -g` on every snapshot |
| Cycles, capacity, condition, adapter rating | the last cached values | `system_profiler`, refreshed when its 5-minute cache has expired, and on launch, manual refresh and after a mode change |
| Processes spawned | none | `pmset -g`, plus `system_profiler` about every 5 minutes |

The cheap snapshot is used only for the timer refresh while the panel is closed, and only when the menu bar is not set to show the power in watts. Everything else takes the full snapshot. The cheap snapshot reuses the details of the last full one, so the values that change slowly stay on screen.

While the panel is closed, Watty therefore wakes every 30 seconds to read the battery and take CPU, memory and temperature samples without starting a process, and about once a minute it samples the per-app list, which runs `ps` once. The footer of the panel shows what triggered the last snapshot and how long it took, for example `Last refresh: timer · 13 ms`.

### Freshness

The strip under the header says how fresh the data is: `Connecting to power telemetry…` before the first reading, `Updated N s ago`, `Refreshing…` after you press the refresh button, and `Stale · updated N s ago` once 45 seconds pass without an update.

## Battery and power flow

The level, state and time estimates are the ones macOS computes. While macOS has no estimate yet, for example right after plugging in or unplugging, the panel says `Calculating time to full` or `Calculating time left`.

Battery power is voltage times current from the registry, with the sign positive while charging and negative while discharging. If those two are not available, or the result is not plausible, the battery controller's own power reading is used.

The panel draws the power flow as three nodes with arrows between them:

- **Adapter**: what the charger delivers right now (the controller's `SystemPowerIn`), with its rated wattage. Unplugged, it says so.
- **System**: what the Mac itself consumes (`SystemLoad`). If the controller does not report it, or reports a negative value as it can for a moment after unplugging, Watty derives it: on the charger, the adapter input minus what goes into the battery (so plus what the battery gives while it supplements the adapter); on battery, the discharge power.
- **Battery**: how fast the battery charges or discharges. Without the adapter the battery can only be discharging, so a positive reading right after unplugging, which the controller can briefly keep, is reported as discharging, in the panel and in `watty`. Below 0.4 W the battery counts as idle. While the charger cannot keep up (see below) it shows the average power of the last minutes, in orange and labelled `draining`, instead of the instantaneous reading.

The arrow from the adapter lights up while the charger supplies more than 0.5 W. The arrow between the system and the battery points toward the battery while charging and toward the system while discharging or draining, and dims when the battery is idle.

Macs differ in what their battery controller reports. A value a Mac does not provide shows as `---`; it is never replaced by a zero.

## Is the battery really charging?

macOS says `Charging` whenever a charger is connected and charging has not been stopped, even when the Mac uses more power than the charger delivers and the battery is losing charge. A 20 W charger on a MacBook running several builds is the usual case: the level falls from 27% to 6% in 22 minutes while macOS keeps reporting `IsCharging = Yes` and an estimate of hours to full. Watty does not take that flag at face value. It decides what the battery is really doing, its **net flow**, from two kinds of evidence.

**Battery power, averaged.** An instantaneous battery power reading says little under a bursty load. The controller refreshes its registry between 5 and 60 seconds apart (about every 15 seconds under a bursty load, up to a minute otherwise), and a reading is the power at one instant: in a recorded minute it said +28 W while the average of that minute was −1.8 W. The controller also keeps accumulators in `PowerTelemetryData`: the sum of the battery power over every tick (`AccumulatedBatteryPower` for charging ticks, `AccumulatedBatteryDischarge` for discharging ones) and the number of ticks (`BatteryPowerAccumulatorCount`, `BatteryDischargeAccumulatorCount`), about one tick per second. Each time they advance, Watty divides the change of the sums by the change of the ticks, which is the average power of the interval since the previous refresh, and averages the intervals seen in the last 150 seconds, weighting each by its ticks. Without the accumulators it averages the instantaneous readings instead, weighting each by the time it covers, and trusts that average only after 30 seconds of readings.

**Level trend.** The median slope of the charge level over the last 8 minutes, in points per minute (the median of the slopes between every pair of points at least 2 minutes apart, so a point or two of jitter, which a heavy load causes within seconds, cannot move it). It counts as falling or rising only when the slope is at least 0.3 points per minute and the level changed by at least 3 points over the window. It is corroborating evidence: it decides when no battery power is available, and it vetoes a weak drain (between −2 W and −5 W) when the level is clearly rising. A stronger drain is never vetoed, because a level that was rising a few minutes ago says nothing about the last minute.

The decision, with the thresholds that stop it from flickering:

| Plugged in, and the average battery power is... | Net flow |
| --- | --- |
| −2 W or lower (stays so until it recovers above −0.5 W) | `draining` |
| +0.5 W or higher while macOS says it is charging (stays so until it falls below +0.25 W) | `charging` |
| anything else, or macOS says it is not charging | `holding` |

On battery the battery can only discharge, so the net flow is `draining` there too, and Watty shows `On battery` as before. With no battery power reading, a falling level means `draining` (until it falls slower than 0.15 points per minute), a rising level while macOS says it charges means `charging`, and an unclear level leaves the net flow unknown while macOS says it charges, or `holding` while it does not.

Plugging in or unplugging, and a gap of more than 2 minutes between readings (the Mac slept), start a new estimate, because the registry can still describe the situation before the event. For the next 90 seconds Watty ignores instantaneous readings, and it takes an accumulator interval into account only once it starts after the event. Until there is evidence the net flow stays unknown and the panel shows what macOS reports. When Watty starts, the estimate starts from the level of the last 8 minutes of the saved history, so a restart does not lose the evidence. That holds when the history was saved less than 5 minutes before the first reading, which a normal quit or restart guarantees and a crash may not.

Only `draining` while plugged in changes what you see:

- the header and the overview say `Plugged in, draining`, in orange, with a warning icon in place of the bolt on the header and on the ring;
- the line under the level says `The 20 W adapter can't keep up` (with the rated power when known) instead of the time to full that macOS estimates; when macOS itself reports that it is not charging, as with a charge limiter that discharges on purpose, the line says `Using the battery while plugged in` instead, because the adapter is not to blame;
- the menu bar icon changes and VoiceOver says `Battery 18%, plugged in, draining`;
- the power flow shows the averaged battery power and `draining`;
- the charge limit and the full battery reminders do not treat the battery as charging;
- the history chart shades in orange the stretches plugged in where the level fell (see [History and notifications](#history-and-notifications)).

The net flow lags reality by about a minute, on purpose: a drain that lasts less than that is not worth announcing. In `watty`, `battery.net_flow` carries the same decision (see the [command line reference](cli.md#battery)); `status` has only one reading to judge from.

The accumulators were checked on the Mac Watty is developed on (Apple M5 Pro, macOS 27.2) against an independent measurement: the gauge chip's own coulomb counter (`PackCurrentAccumulator` and its count in `AppleSmartBatteryPack`), over a 15 minute recording under alternating CPU load with the 45 W charger connected. In 60 second windows their average differed from the gauge's by 0.34 W on average, 2% of the 16.8 W typical size of the windows, with a slope of 1.001 and a correlation of 0.9993, and always on the same side of zero (28 windows of 28). The instantaneous reading differed by 16.8 W on average and had the wrong sign in 8 of the 28 windows. Other Macs may expose these keys differently; when they are missing Watty uses the instantaneous readings.

## Energy by app

The list ranks apps by their share of CPU time and shows each app's memory footprint. It tells you who keeps the CPU busy. It is not a measurement in watts.

How a sample works:

- For your own processes, Watty reads the cumulative CPU time (user plus system) and the physical memory footprint with `proc_pid_rusage`, directly in the app. The CPU time is a count of Mach ticks, converted to seconds with the Mach timebase. A pass over all processes takes a few milliseconds.
- A share is the CPU time used between two samples divided by the time between them. 100% is one fully used core, so a busy multi-threaded app can exceed 100%. Anything under 0.2% is left out.
- macOS does not let a normal user read other users' processes this way. For those, such as `WindowServer` and root daemons, the CPU time comes from `ps -A -o pid=,uid=,cputime=,comm=`, in hundredths of a second, and no memory figure is shown. A pass of `ps` takes tens of milliseconds, about 40 ms on an Apple Silicon MacBook.
- Processes are grouped under the outermost `.app` bundle of their executable, so a browser appears once rather than as dozens of helpers, with the app's name and icon. Processes outside a bundle appear under their executable name. Memory footprints are added up across the group.
- Watty itself, a few system processes (`launchd`, `logd`, `trustd`) and the tools it runs (`ioreg`, `pmset`, `system_profiler`) are left out. Each sample keeps the 25 busiest apps; the panel lists the top 5 and `watty top` up to 25.
- The first sample after launch has nothing to compare with, so the panel says `Measuring per-app CPU` until the second one arrives.

### Why CPU share and not energy

- The same `proc_pid_rusage` call has a per-process "billed energy" counter. In testing on Apple Silicon it stayed at 0 for a process using a full core, so it cannot rank anything.
- `powermetrics` reports a per-process energy impact, but it needs administrator rights, and Watty does not run privileged code to monitor.
- CPU share is what an unprivileged process can measure reliably. It points at the right apps most of the time, but it misses energy spent elsewhere (GPU, Neural Engine, network, display), it does not tell an efficiency core from a performance core, and it is not in watts. Read the list as "what is working hardest", not as "what drains the battery".

## Activity and temperature

- **CPU** is the difference between two readings of the system tick counters (user, system, idle, nice), shown as a total with its user and system parts.
- **Memory** is app memory (internal pages minus purgeable ones) plus wired plus compressed memory, the same breakdown Activity Monitor shows as Memory Used, as a share of the physical memory. The swap in use comes from `vm.swapusage`.
- **SoC temperature** is the hottest of the chip's die sensors, read from the IOKit HID temperature services. The tooltip of the temperature label gives the average and the number of sensors.

Samples are taken with every snapshot and the charts show the last 10 minutes, up to 400 samples. A chart says `Collecting` until it has two points.

The HID temperature calls are not in Apple's public headers, so a future macOS release could change them. Watty looks for the die sensors of Apple Silicon chips by name. Intel Macs and virtual machines generally expose none of those, and there the temperature shows as `---`; Watty then retries only every 5 minutes instead of on every sample.

## Battery health

The health section shows cycle count, maximum capacity, condition, battery temperature, voltage and current. Cycles, capacity and condition come from `system_profiler`, cached for 5 minutes because they change slowly; the registry fills in cycles and capacity when `system_profiler` is unavailable. Voltage, current and temperature come from the registry on every snapshot.

The section is collapsed to one line by default, and Watty remembers whether you expanded it.

## Energy mode

The current mode is read from `pmset -g`: `powermode` is 0 for Automatic, 1 for Low Power and 2 for High Power, with the older `lowpowermode` and `highpowermode` keys as a fallback. If `pmset` reports no mode at all, Watty falls back to Low Power Mode as the power sources report it, and then to the mode fields of `system_profiler`.

Which modes the control offers depends on what the Mac reports (`pmset -g cap` for its capabilities, `pmset -g` for its current settings). Automatic is always there; Low Power and High Power appear only where the machine supports them.

Choosing a mode runs `pmset -a powermode N` (or the older keys on a Mac that lacks `powermode`) through the standard macOS authorization prompt, for all power sources. Watty asks `osascript` to run the command with administrator privileges, so macOS shows the prompt and Watty never sees the password. If you cancel, the system refuses or it keeps another mode, the control goes back to the real mode and says why, for example `System kept Automatic`.

## History and notifications

**Battery history.** About once a minute, and whenever the level, the charging state or the adapter state changes, Watty records a sample: time, level, whether the battery was charging and whether the adapter was connected. Samples older than 24 hours are dropped, and at most 4,000 are kept. The chart shows the last 1, 6 or 24 hours, with charging periods shaded in green and, in orange, the periods plugged in where the level actually fell. A gap of more than 10 minutes, for example while the Mac slept or Watty was not running, breaks the line instead of drawing a straight segment across it.

**Plugged-in drains in the chart.** The file keeps what macOS reported, a charging flag even when the charger could not keep up, and Watty does not rewrite it. When it draws the chart it looks for the stretches with the adapter connected where the level fell by at least 3 points without recovering 3 points. It smooths the level with a median over 3 minutes first, so the jitter of a heavy load does not count. Those stretches are drawn in orange, with the legend `Plugged in, draining`, instead of green. The search runs over the whole saved history, so the 1, 6 and 24 hour views agree, and it needs no new field in the file.

The history is written at most every 5 minutes, and also when Watty quits or is stopped with SIGTERM or SIGINT, and before the Mac sleeps. Writes are atomic. A history file that cannot be read is set aside as `battery-history.corrupt.json` and a new one starts. If the file cannot be saved at all, the panel footer says `Battery history can't be saved`.

**Notifications.** All three are off by default and only exist on Macs with a battery. macOS asks for permission when you turn the first one on.

- *Low battery* fires once when the battery is at or below its level (5% to 50%, 20% by default) while running on battery power.
- *Charge limit reminder* fires once when charging reaches its level (50% to 100%, 80% by default). It reminds you to unplug; Watty does not stop the charge.
- *Fully charged* fires once when the battery is full on the charger.

While the charger cannot keep up the battery counts as neither charging nor full, so the charge limit and fully charged reminders do not fire for it. The low battery alert still applies only on battery power.

An alert that has fired stays quiet until the situation clears: the level moves 2 points back past its threshold (5 points for fully charged), or you plug or unplug the charger. Turning an alert on, or changing its level, while its condition already holds does not fire it. Clicking a notification opens the panel.

## Desktop Macs

Watty decides a Mac has a battery by looking for an internal battery in the IOKit power sources or an `AppleSmartBattery` service. With neither, it treats the Mac as a desktop and hides the battery, charger and health sections, the history chart and the battery notifications. The menu bar shows the CPU usage instead of the percentage, or only the icon. CPU, memory, temperature, per-app load and the energy mode work as on a MacBook.

## What is stored and where

| What | Where |
| --- | --- |
| Battery history: time, level, charging and adapter flags for the last 24 hours | `~/Library/Application Support/Watty/battery-history.json` |
| Settings: menu bar display, history range, whether health is expanded, notification choices | `~/Library/Preferences/com.jmtes.watty.plist` |
| Diagnostics | The macOS unified log, subsystem `com.jmtes.watty`; service logs when run as a service |

Nothing else is stored: no app names, no per-app history, no identifiers. Nothing leaves the Mac. See [Privacy](../README.md#privacy).

## Limits

- Values come from what macOS reports and are rounded for display. Time estimates are macOS's own.
- Whether the battery is really charging is judged over the last minutes. A change shows after about a minute, a battery that loses less than 2 W is not called draining, and for 90 seconds after plugging in or waking the Mac Watty waits for fresh readings and shows what macOS reports.
- The average battery power relies on accumulators that were checked on one Mac. Where they are missing, Watty averages the instantaneous readings, which are far less reliable under a bursty load.
- The per-app list is a CPU ranking. It misses GPU, Neural Engine, network and display energy, and it misses processes that start and exit between two samples.
- Other users' processes (system daemons, `WindowServer`) have a CPU share but no memory figure, and their CPU time has a resolution of 10 ms.
- The temperature sensors are the ones of Apple Silicon chips, and they are read through an interface Apple does not document.
- What the battery controller reports varies by Mac. Fields it does not provide show as `---`.
- A Mac without a battery has no battery, charger or health readings at all; those sections are hidden. See [Desktop Macs](#desktop-macs).
- The energy modes offered, and when macOS honors a change, are decided by macOS.

## Logs and debugging

Watty logs through the unified logging system under the subsystem `com.jmtes.watty`. Use the full path of `log`, because zsh has a built-in command of the same name:

```sh
/usr/bin/log stream --predicate 'subsystem == "com.jmtes.watty"' --level debug
/usr/bin/log show --last 1h --info --predicate 'subsystem == "com.jmtes.watty"'
```

When Watty runs as a service, its standard output and error also go to a file: `$(brew --prefix)/var/log/watty.log` with Homebrew, or `~/Library/Logs/Watty/stderr.log` with the LaunchAgent that `make install LAUNCH_AGENT=1` creates. The service restarts the app after a crash but not after a normal Quit.

## What it does not do

- It does not touch the network, send analytics or look for updates.
- It does not change anything on your Mac except the energy mode you pick, the login item you turn on, and its own settings and history.
- It does not limit charging. To cap the charge at a level, use [BatFi](https://github.com/rurza/BatFi).
- It does not claim lab precision.
