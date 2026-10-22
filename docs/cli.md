# Watty command line

`watty` is the terminal companion of the Watty menu bar app. It reads the same telemetry
(battery, charger, power flow, temperatures, CPU, memory and per-app load) and prints it as text or
JSON, so you can use it in scripts, in status bars such as SketchyBar or tmux, or for a quick check.

It only reads system state. It needs no administrator rights and does not require the app to be
running, except for `watty show`, which brings the app's panel to the front.

- [Install](#install)
- [Quick start](#quick-start)
- [Commands](#commands)
- [Output conventions](#output-conventions)
- [Exit codes](#exit-codes)
- [JSON schema](#json-schema)
- [Recipes](#recipes)
- [Troubleshooting](#troubleshooting)

## Install

With Homebrew the command is installed as `watty`:

```sh
brew install jmt-es/tap/watty
```

Without Homebrew the command is the `watty-cli` executable inside the app. Link it into a directory
on your `PATH`:

```sh
sudo mkdir -p /usr/local/bin
sudo ln -sf /Applications/Watty.app/Contents/MacOS/watty-cli /usr/local/bin/watty
```

When you build from source, `make install BIN_DIR=~/.local/bin` installs the app and creates that
link for you (add the directory to your `PATH` if it is not there yet).

Requires macOS 13 or later.

## Quick start

```sh
watty                        # same as: watty status
watty status --json | jq .battery
watty top --limit 5          # what is using the CPU right now
watty watch                  # live view, Ctrl-C to quit
watty show                   # bring up the Watty panel
```

## Commands

### `watty status [--json]`

Prints one snapshot: battery level, charge state (and whether the battery is really charging or
draining), time remaining, power source and charger rating, system input, system load and battery
power, voltage, amperage, battery temperature, cycle count, maximum capacity and condition, power
mode and Low Power Mode, SoC temperature, CPU and memory.

```console
$ watty status
Battery        84% · Charging · 1:09 to full
Power source   Power adapter · 70 W rated
System input   66.3 W
System load    32.8 W
Battery power  +33.4 W · charging
Voltage        12.61 V
Amperage       +2.65 A
Battery temp   36.4 °C
Cycles         257
Max capacity   89%
Condition      Normal
Power mode     High Power · Low Power Mode off
SoC temp       82.7 °C
CPU            31.8% · user 18.6% · system 13.2%
Memory         74.7% · 47.8 GB of 64.0 GB · swap 1.94 GB
```

CPU usage needs two readings, so the command samples it over about half a second. The whole command
takes under a second on an Apple silicon MacBook; do not poll it faster than every few seconds (use
[`watch`](#watty-watch---interval-seconds) for a continuous feed).

Battery power is signed: positive while charging, negative while discharging. The same applies to
the amperage.

The `Battery` line says `Plugged in, draining` when the Mac is plugged in but the battery is losing
charge, which happens when the charger delivers less than the Mac uses. macOS keeps reporting
`Charging` in that situation, and an estimate of hours to full; `watty` does not repeat it:

```console
$ watty status
Battery        18% · Plugged in, draining · the 20 W adapter can't keep up
Power source   Power adapter · 20 W rated
System input   19.7 W
System load    38.0 W
Battery power  -18.3 W · draining
...
```

`status` reads the battery once, so it judges from that single reading: what the battery is doing
at that instant. The battery controller refreshes its readings every 5 to 60 seconds, so the reading
can be up to a minute old, and under a bursty load one reading can mislead (a spike of positive power
in the middle of a drain, for example). For the judgement Watty makes over the last minutes, as the
panel does, use [`watch`](#watty-watch---interval-seconds). A value you can rely on in a script is
[`net_flow`](#battery) from several readings, not one.

On a Mac without a battery the battery rows are replaced by a single line, and the power mode, SoC
temperature, CPU and memory are still shown:

```console
$ watty status
Battery     none detected
Power mode  Automatic · Low Power Mode off
SoC temp    41.6 °C
CPU         3.5% · user 2.4% · system 1.1%
Memory      53.0% · 8.48 GB of 16.0 GB
```

| Option   | Description                                                              |
| -------- | ------------------------------------------------------------------------ |
| `--json` | Print one JSON document instead of text. See the [schema](#json-schema). |

### `watty top [--json] [--limit N] [--interval SECONDS]`

Lists the apps using the most CPU. The command takes two process samples `--interval` seconds apart
and reports each app's CPU share over that window, together with its memory footprint. Helper
processes of one app (for example browser renderers) are added up under the app's name.

```console
$ watty top --limit 5
Top apps by CPU · averaged over 1 s
    CPU     MEMORY  APP
 125.3%     175 MB  Xcode
  46.0%          —  WindowServer
  45.4%     390 MB  Visual Studio Code
  42.0%    2.11 GB  Google Chrome
  16.3%     820 MB  Slack
```

A CPU share of 100% is one fully used core, so busy multi-threaded apps can exceed 100%. It is a
share of CPU time, not a measurement in watts; see
[how it works](how-it-works.md#energy-by-app). Memory is shown as `—` for processes whose memory
Watty cannot read (system daemons and other users' processes). When no app is above 0.2% CPU the
command says so instead of printing a table.

On a terminal, long app names are cut to the width of the window. When the output is piped they are
never truncated.

| Option                | Default | Description                                                                 |
| --------------------- | ------- | --------------------------------------------------------------------------- |
| `--limit N`           | `10`    | Maximum number of apps to list. Must be a positive integer.                 |
| `--interval SECONDS`  | `1`     | Sampling window, from `0.5` to `3600` seconds.                              |
| `--json`              |         | Print one JSON document instead of a table. See the [schema](#json-schema). |

The sampler keeps the 25 busiest apps, so `--limit` values above 25 list at most 25 apps.

### `watty watch [--interval SECONDS]`

A live view of the same readings as `status`, refreshed every `--interval` seconds (default `2`,
from `0.5` to `3600`).

On a terminal the screen is redrawn in place and restored when you press Ctrl-C. Color is used
unless `NO_COLOR` is set, and `TERM=dumb` falls back to the line output below.

When the output is not a terminal (a pipe or a file) it prints one compact line per sample and
flushes after each, so it is safe to follow with `tail -f`, `awk` or `read`:

```console
$ watty watch --interval 5 | cat
2026-10-21T18:04:21+02:00 level=82 state=charging battery_w=+45.4 system_w=20.3 net_flow=charging
2026-10-21T18:04:26+02:00 level=82 state=charging battery_w=+45.1 system_w=20.6 net_flow=charging
```

| Field       | Meaning                                                                              |
| ----------- | ------------------------------------------------------------------------------------ |
| time        | ISO 8601 local time with its UTC offset.                                             |
| `level`     | Battery level in percent.                                                            |
| `state`     | `charging`, `charged`, `plugged_in_not_charging`, `on_battery`, or `no_battery`. What macOS reports. |
| `battery_w` | Battery power in watts, signed: positive while charging, negative while discharging. The reading of that instant. |
| `system_w`  | Power used by the Mac in watts (system load).                                        |
| `net_flow`  | Where the battery is really heading, judged over the last minutes: `charging`, `draining` or `holding`. See [`battery.net_flow`](#battery). |

`watch` keeps the readings of the samples it has taken, so unlike `status` it judges `net_flow` over
time. With a charger that cannot keep up, `state` still says `charging` and the instantaneous
`battery_w` jumps around, while `net_flow` holds the verdict:

```console
$ watty watch --interval 15 | cat
2026-10-21T21:29:45+02:00 level=19 state=charging battery_w=-17.9 system_w=37.7 net_flow=—
2026-10-21T21:30:00+02:00 level=19 state=charging battery_w=-17.9 system_w=37.7 net_flow=—
2026-10-21T21:30:15+02:00 level=19 state=charging battery_w=+4.8 system_w=15.1 net_flow=draining
2026-10-21T21:30:30+02:00 level=18 state=charging battery_w=-19.4 system_w=39.0 net_flow=draining
```

On a terminal the `Battery` row of the live screen says `Plugged in, draining` the same way `status`
does, and while it does its `Battery power` row shows the average of the last minutes.

`net_flow` is `—` for the first 30 seconds or so, until there are enough readings, and again for 90
seconds after the charger is plugged in or the Mac wakes up, while the battery controller catches
up. Unknown values are printed as `—` so every line keeps the same six columns. The sixth is
appended at the end, so a script that reads the first five by position is not affected. Warnings
about partial reads go to stderr, once each. When the reader closes the pipe (`watty watch | head
-3`), `watch` stops with exit status 1 and a short message on stderr.

The battery controller only updates its power readings every 5 to 60 seconds, so consecutive samples
can repeat the same power values; a shorter interval mainly makes a change show up sooner.

| Option               | Default | Description                              |
| -------------------- | ------- | ---------------------------------------- |
| `--interval SECONDS` | `2`     | Time between samples, `0.5` to `3600`.   |

### `watty show`

Brings up the Watty panel in a regular window. If the app is running it is asked to show its panel;
otherwise the app is started first. This is handy when the menu bar icon is hidden behind the notch
or a menu bar manager. It prints nothing on success.

If Watty.app cannot be found the command exits with an error that explains how to install it.

### Help and version

```sh
watty help                  # overview of the commands
watty help top              # same as: watty top --help
watty status -h             # every command accepts --help and -h
watty --version             # watty 1.3.1 (-v works too)
```

## Output conventions

- Data goes to stdout. Warnings, errors and usage messages go to stderr, so `watty status
  --json` can always be piped straight into a parser.
- Values carry their unit: `W`, `V`, `A`, `°C`, `%`, `GB`. Memory sizes use binary units (1 GB is
  1024 MB), as the Watty panel does.
- A value that cannot be read prints as `—` in text and is `null` in JSON. It is never replaced by
  a zero.
- Text output is meant to fit in 80 columns. The one-line-per-sample output of `watch` is the
  exception: it carries six fields and runs a little longer.
- Bold and color are used only when stdout is a terminal and the `NO_COLOR` environment variable
  is unset or empty. JSON output is never styled.
- Partial read failures (for example `system_profiler` timing out) do not stop the command: the
  data that could be read is printed, each problem is written to stderr as
  `watty: warning: ...`, and the JSON `warnings` array lists them.

## Exit codes

| Code | Meaning                                                                                              |
| ---- | ---------------------------------------------------------------------------------------------------- |
| `0`  | Success.                                                                                             |
| `64` | Usage error: unknown command or option, missing or invalid value. A message and the short usage are printed to stderr. |
| `1`  | Runtime failure, for example the process sampler returned no data, Watty.app is not installed (`show`), or stdout cannot be written. |

`watch` runs until you stop it. Ctrl-C restores the terminal and ends the process with the usual
interrupted status (130 in most shells).

```console
$ watty top --limit abc
watty: invalid value 'abc' for '--limit': expected a positive integer
usage: watty top [--json] [--limit N] [--interval SECONDS]
Try 'watty top --help' for more information.
$ echo $?
64
```

## JSON schema

`status --json` and `top --json` print one pretty-printed JSON document with sorted keys. Keys are
snake_case, and the unit is part of the key name. Unknown values are explicit `null`s: a key is
never omitted.

All timestamps in JSON are ISO 8601 in UTC (`2026-10-21T16:12:57Z`).

Numbers are rounded for readability: watts to 0.01, volts and amps to 0.001, temperatures and
percentages to 0.1.

### `watty status --json`

```json
{
  "battery": {
    "amperage_amps": -4.79,
    "condition": "Normal",
    "cycle_count": 257,
    "level_percent": 87,
    "maximum_capacity_percent": 89,
    "net_flow": "draining",
    "power_watts": -57.9,
    "state": "on_battery",
    "temperature_celsius": 37.4,
    "time_to_empty_minutes": 75,
    "time_to_full_minutes": null,
    "voltage_volts": 12.087
  },
  "has_battery": true,
  "power": {
    "adapter_rated_watts": null,
    "low_power_mode_active": false,
    "mode": "high_power",
    "source": "battery",
    "system_input_watts": 0,
    "system_load_watts": 57.9
  },
  "schema_version": 1,
  "system": {
    "cpu_percent": 27.6,
    "cpu_system_percent": 12.4,
    "cpu_user_percent": 15.2,
    "memory_percent": 72.9,
    "memory_total_bytes": 68719476736,
    "memory_used_bytes": 50110038016,
    "soc_temperature_celsius": 66.1,
    "swap_used_bytes": 2081488896
  },
  "timestamp": "2026-10-21T16:12:57Z",
  "warnings": [],
  "watty_version": "1.3.1"
}
```

The example is shown as `jq .` prints it. The tool's own formatter writes the same document with a
space before each colon and puts an empty array on three lines.

#### Top level

| Key              | Type    | Description                                                                          |
| ---------------- | ------- | ------------------------------------------------------------------------------------ |
| `schema_version` | integer | Version of this schema. `1`.                                                         |
| `watty_version`  | string  | Watty version that produced the document.                                            |
| `timestamp`      | string  | When the report was generated (UTC).                                                 |
| `has_battery`    | boolean | `false` on Macs without a battery.                                                   |
| `battery`        | object  | Battery readings. Always present; every field is `null` when `has_battery` is `false`. |
| `power`          | object  | Power source, charger and power mode. Always present.                                |
| `system`         | object  | SoC temperature, CPU and memory. Always present.                                     |
| `warnings`       | array   | Strings describing readings that failed (for example `"system_profiler detail read failed"`). Empty when everything was read. Free text, not a stable list. |

#### `battery`

| Key                        | Type    | Unit    | Description |
| -------------------------- | ------- | ------- | ----------- |
| `level_percent`            | integer | percent | Charge level, 0 to 100. |
| `state`                    | string  |         | `charging`, `charged`, `plugged_in_not_charging` or `on_battery`. What macOS reports. |
| `net_flow`                 | string  |         | Where the battery is really heading: `charging`, `draining` or `holding`. `null` when unknown and on Macs without a battery. See below. |
| `time_to_full_minutes`     | integer | minutes | Estimated time to a full charge. Only while `charging`; `null` while macOS is still estimating, and `null` while `net_flow` is `draining`. |
| `time_to_empty_minutes`    | integer | minutes | Estimated time left. Only while `on_battery`; `null` while macOS is still estimating. |
| `power_watts`              | number  | W       | Power flowing into the battery at the moment of the reading. Positive while charging, negative while discharging. |
| `voltage_volts`            | number  | V       | Battery voltage. |
| `amperage_amps`            | number  | A       | Battery current, signed like `power_watts`. |
| `temperature_celsius`      | number  | °C      | Battery temperature. |
| `cycle_count`              | integer |         | Charge cycles. |
| `maximum_capacity_percent` | integer | percent | Maximum capacity relative to the design capacity. |
| `condition`                | string  |         | Battery condition as macOS reports it (`Normal`, `Service Recommended`, ...). |

`state` is what macOS reports, and `net_flow` is what the battery does. They agree most of the time.
They differ when the charger cannot keep up with the Mac: macOS keeps saying the battery is charging
while the level falls.

| `state`                   | `net_flow`  | Situation |
| ------------------------- | ----------- | --------- |
| `charging`                | `charging`  | The battery gains charge. |
| `charging`                | `draining`  | Plugged in, but the Mac uses more than the charger delivers: the battery loses charge. |
| `charging`                | `holding`   | Plugged in and balanced: the battery neither gains nor loses charge. |
| `plugged_in_not_charging` | `holding`   | Plugged in and not charging, for example at the limit of optimized charging. |
| `plugged_in_not_charging` | `draining`  | Plugged in, macOS is not charging and the Mac still uses more than the charger delivers. |
| `charged`                 | `holding`   | Full. |
| `charged`                 | `draining`  | Full, but the Mac uses more than the charger delivers. |
| `on_battery`              | `draining`  | Unplugged: the battery can only discharge. |

`net_flow` is the average battery power over the last 2 and a half minutes, backed by the trend of the
level over the last 8 minutes (the [how it works](how-it-works.md#is-the-battery-really-charging) page
has the rules): `draining` at −2 W or lower, `charging` at +0.5 W or higher while macOS says it is
charging, `holding` otherwise, and `null` when there is not enough data. In `status` that average is
the single reading of the moment, so it can mislead under a bursty load; in `watch` it is the
average over the samples taken so far.

#### `power`

| Key                     | Type    | Unit | Description |
| ----------------------- | ------- | ---- | ----------- |
| `source`                | string  |      | `adapter` or `battery`. `null` when unknown and on Macs without a battery. |
| `adapter_rated_watts`   | integer | W    | Rated power of the connected charger. `null` on battery. |
| `system_input_watts`    | number  | W    | Power drawn from the adapter. `0` while running on battery. |
| `system_load_watts`     | number  | W    | Power used by the Mac. Reported by the power controller; when it is not available it is derived from the adapter input and the battery power. |
| `mode`                  | string  |      | The energy mode setting: `automatic`, `low_power` or `high_power`. |
| `low_power_mode_active` | boolean |      | Whether Low Power Mode is in effect right now. |

#### `system`

| Key                       | Type    | Unit    | Description |
| ------------------------- | ------- | ------- | ----------- |
| `soc_temperature_celsius` | number  | °C      | Hottest SoC die sensor. `null` on Macs that expose none. |
| `cpu_percent`             | number  | percent | Total CPU usage over a half-second window (`cpu_user_percent` + `cpu_system_percent`). |
| `cpu_user_percent`        | number  | percent | Share spent in user code. |
| `cpu_system_percent`      | number  | percent | Share spent in the kernel. |
| `memory_percent`          | number  | percent | Used memory as a share of physical memory. |
| `memory_used_bytes`       | integer | bytes   | App, wired and compressed memory, the way Activity Monitor adds it up. |
| `memory_total_bytes`      | integer | bytes   | Physical memory. |
| `swap_used_bytes`         | integer | bytes   | Swap in use. |

#### Macs without a battery

`has_battery` is `false` and every `battery` field is `null`. Power mode, SoC temperature, CPU and
memory are still reported:

```json
{
  "battery": {
    "amperage_amps": null,
    "condition": null,
    "cycle_count": null,
    "level_percent": null,
    "maximum_capacity_percent": null,
    "net_flow": null,
    "power_watts": null,
    "state": null,
    "temperature_celsius": null,
    "time_to_empty_minutes": null,
    "time_to_full_minutes": null,
    "voltage_volts": null
  },
  "has_battery": false,
  "power": {
    "adapter_rated_watts": null,
    "low_power_mode_active": false,
    "mode": "automatic",
    "source": null,
    "system_input_watts": null,
    "system_load_watts": null
  },
  "schema_version": 1,
  "system": {
    "cpu_percent": 3.5,
    "cpu_system_percent": 1.1,
    "cpu_user_percent": 2.4,
    "memory_percent": 53,
    "memory_total_bytes": 17179869184,
    "memory_used_bytes": 9100000000,
    "soc_temperature_celsius": 41.6,
    "swap_used_bytes": 0
  },
  "timestamp": "2026-10-21T16:04:04Z",
  "warnings": [],
  "watty_version": "1.3.1"
}
```

### `watty top --json`

```json
{
  "consumers": [
    { "cpu_percent": 125.3, "memory_bytes": 183500800, "name": "Xcode" },
    { "cpu_percent": 46, "memory_bytes": null, "name": "WindowServer" },
    { "cpu_percent": 45.4, "memory_bytes": 408944640, "name": "Visual Studio Code" }
  ],
  "interval_seconds": 1,
  "schema_version": 1,
  "timestamp": "2026-10-21T16:14:51Z",
  "watty_version": "1.3.1"
}
```

| Key                | Type    | Unit    | Description |
| ------------------ | ------- | ------- | ----------- |
| `schema_version`   | integer |         | Version of this schema. `1`. |
| `watty_version`    | string  |         | Watty version that produced the document. |
| `timestamp`        | string  |         | When the report was generated (UTC). |
| `interval_seconds` | number  | seconds | The sampling interval that was requested. |
| `consumers`        | array   |         | Apps sorted by `cpu_percent`, highest first, at most `--limit` of them. Empty when no app is above 0.2% CPU. |

Each entry of `consumers`:

| Key            | Type    | Unit    | Description |
| -------------- | ------- | ------- | ----------- |
| `name`         | string  |         | App or process name. Helper processes are folded into their app. |
| `cpu_percent`  | number  | percent | CPU share over the interval. 100 is one fully used core, so it can exceed 100. |
| `memory_bytes` | integer | bytes   | Physical memory footprint. `null` for processes whose memory cannot be read. |

### Stability

`schema_version` changes only when an existing key is removed, renamed or changes type, or when its
meaning changes. New keys can be added at any time without changing the version, so parse the
document with a tolerant reader (`jq`, `json.loads`, `JSON.parse`) and look keys up by name.

## Recipes

Battery level for a status bar:

```sh
watty status --json | jq -r '"\(.battery.level_percent)% \(.battery.state)"'
# 87% on_battery
```

On a Mac without a battery `.battery.level_percent` is `null`; use
`jq -r 'if .has_battery then "\(.battery.level_percent)%" else "AC" end'` to handle both.

Time left, or time to full:

```sh
watty status --json | jq -r '.battery | (.time_to_empty_minutes // .time_to_full_minutes // empty) | "\(./60|floor)h\(.%60|floor)m"'
# 1h15m
```

### SketchyBar

`plugins/battery.sh`, run every 30 s with `update_freq=30`:

```sh
#!/bin/sh
LEVEL=$(watty status --json | jq -r '.battery.level_percent // empty')
sketchybar --set "$NAME" label="${LEVEL}%"
```

### tmux

In `~/.tmux.conf`. tmux runs the status text through `strftime`, so a literal percent sign is
written `%%`:

```tmux
set -g status-interval 15
set -g status-right '#(watty status --json | jq -r "\"\(.battery.level_percent)%% \(.battery.power_watts) W\"")'
```

### Notice a charger that cannot keep up

`watch` judges over time, so it is the right feed for this. It prints the line when the battery is
losing charge although the Mac is plugged in:

```sh
watty watch --interval 15 |
  awk '/state=(charging|plugged_in_not_charging)/ && /net_flow=draining/ { print "the charger cannot keep up"; fflush() }'
```

For a one-off check, `watty status --json | jq -e '.battery.net_flow == "draining" and .battery.state != "on_battery"'`
exits with status 0 only in that situation. It judges from one reading, so run it a few times before
trusting a single answer.

### Run something when the battery is low

```sh
if watty status --json | jq -e '.battery.state == "on_battery" and .battery.level_percent < 20' >/dev/null; then
  echo "Battery low, plug in the charger"
fi
```

`jq -e` exits non-zero when the expression is false or `null`, which is also what happens on a Mac
without a battery.

### Log the power flow to a CSV file

```sh
watty watch --interval 60 |
  awk '{ gsub(/[a-z_]+=/, ""); gsub(/ /, ","); print; fflush() }' >> ~/battery-log.csv
```

```text
2026-10-21T18:19:13+02:00,84,charging,+31.8,49.4
```

### What is using the CPU

```sh
watty top --limit 3 --json | jq -r '.consumers[] | "\(.cpu_percent)% \(.name)"'
```

## Troubleshooting

**`watty: Watty.app is not installed`**: `watty show` needs the app. Install it and run
the command again. Every other command works without the app.

**The menu bar icon is hidden.** On Macs with a notch, or with a menu bar manager, the icon can end
up out of sight. `watty show` opens the panel without it; from there, Settings lets you choose a
narrower menu bar display, such as the icon alone.

**Some values are `—` or `null`.** The Mac does not provide that reading (for example no battery,
or no charger connected) or it could not be read this time. Check the `warnings` array in the JSON
output, or the `watty: warning:` lines on stderr.

**`net_flow` is `null` or `—`.** There is no battery, or `watch` has not taken enough readings yet
(about 30 seconds), or the charger was plugged in or the Mac woke up less than 90 seconds ago.
`status` shows it from its first reading as long as the battery power is known.

**Colors or cursor control look wrong.** Set `NO_COLOR=1` to turn off bold and color. With
`TERM=dumb`, `watch` prints plain lines instead of redrawing.
