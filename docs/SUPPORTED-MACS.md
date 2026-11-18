# Which Macs Lidlezz runs on

Last updated: 2026-09-10

## Short answer

**Apple Silicon (M1 and later) MacBook Air and MacBook Pro, macOS 14 Sonoma or later.**
Intel Macs are not supported. On desktop Macs (mini, Studio, iMac, Pro) the app opens, but with no lid its main feature means nothing.

## Why these limits: the technology underneath

| Technology | Used for | Requirement |
|---|---|---|
| Swift 5 / SwiftUI / AppKit (NSStatusItem, NSPopover) | Menu bar app | macOS 14 (`Package.swift` platform, `LSMinimumSystemVersion 14.0`) |
| `SMAppService.daemon` | Registering the root helper | macOS 13+ |
| `NSXPCConnection.setCodeSigningRequirement` | Only the signed Lidlezz app may talk to the helper | macOS 13+ |
| `pmset -a disablesleep 1` | Staying awake with the lid closed | Every Mac; needs root (helper) |
| `pmset -a lowpowermode 1` | Low power in the bag | macOS 12+, Apple Silicon and 2019+ Intel laptops |
| `taskpolicy -b` | Moving Claude Code to efficiency cores | Apple Silicon has P/E cores; on Intel it only lowers priority |
| IOHIDEventSystemClient (private API) `PMU tdie…` / `pACC,eACC MTR Temp Sensor…` | SoC temperature, 85°/95° thresholds | Apple Silicon only; Intel SMC keys differ and are not read |
| `IOPMrootDomain.AppleClamshellState` | Is the lid closed | Laptops only; always open on desktops |
| `IOPSCopyPowerSourcesInfo`, `AppleSmartBattery` | Battery percentage and watts | Macs with a battery |
| `IOPMAssertionCreateWithName(PreventUserIdleSystemSleep)` | Staying awake with the lid open | Every Mac |
| `tmutil disable/enable` | Pausing Time Machine in the bag | Every Mac, root |
| UserNotifications | Notifications | Every Mac |
| Claude Code hooks (`~/.claude/settings.json`) | Session working / finished / waiting for a limit | Claude Code 2.1.234+ (for the limit-wait event) |
| Build target | | arm64 only; Homebrew cask `depends_on arch: :arm64` |

Sensor names change with the chip: M2 and later expose `PMU tdie1…N`, M1 exposes `pACC/eACC MTR Temp Sensor…`. The app takes the hottest `tdie` sensor, falling back to `ACC MTR`. Verified on M4; the M1 fallback is in the code but untested on real hardware.

## Models

Full support = lid-closed mode, temperature guard, battery floor, E-core throttling.

### MacBook Air

| Model | Chip | Year | Status |
|---|---|---|---|
| MacBook Air 13" | M1 | 2020 | Full support, sensor fallback (untested) |
| MacBook Air 13" | M2 | 2022 | Full support |
| MacBook Air 15" | M2 | 2023 | Full support |
| MacBook Air 13" / 15" | M3 | 2024 | Full support |
| MacBook Air 13" / 15" | M4 | 2025 | Full support, development machine |
| MacBook Air 13" / 15" | M5 | 2026 | Full support expected (same sensor family), untested |

The MacBook Air has no fan, so with the lid closed in a bag it reaches the 85° warning threshold sooner than a MacBook Pro.

### MacBook Pro

| Model | Chip | Year | Status |
|---|---|---|---|
| MacBook Pro 13" | M1 | 2020 | Full support, sensor fallback (untested) |
| MacBook Pro 14" / 16" | M1 Pro, M1 Max | 2021 | Full support, sensor fallback (untested) |
| MacBook Pro 13" | M2 | 2022 | Full support |
| MacBook Pro 14" / 16" | M2 Pro, M2 Max | 2023 | Full support |
| MacBook Pro 14" / 16" | M3, M3 Pro, M3 Max | 2023 | Full support |
| MacBook Pro 14" / 16" | M4, M4 Pro, M4 Max | 2024 | Full support |
| MacBook Pro 14" | M5 | October 2025 | Full support expected, untested |
| MacBook Pro 14" / 16" | M5 Pro, M5 Max | March 2026 | Full support expected, untested |

### Desktop Macs (Apple Silicon)

Mac mini (M1–M4), Mac Studio (M1 Max–M4 Ultra), iMac (M1–M4), Mac Pro (M2 Ultra): the app opens, temperature reading and auto start work, but the lid sensor always reports "open" and there is no battery. Lid-closed mode adds nothing here; these machines have no sleep problem to begin with.

### Not supported

- **Intel Macs (2020 and earlier):** the build is arm64, temperature sensors cannot be read, there are no E-cores. Rosetta does not help.
- **macOS 13 Ventura and earlier:** does not launch because of SwiftUI and SMAppService requirements. M1 machines can update to Sonoma for free.

## macOS version

Every Apple Silicon Mac runs macOS 14 Sonoma, 15 Sequoia and 26 Tahoe. Development and testing were done on macOS 26.5; 14 and 15 match the build target but are not tested end to end.

## Test status

| Environment | Tested |
|---|---|
| MacBook Air M4, macOS 26.5 | Every feature, notarized install, Homebrew |
| M1 family | Sensor name fallback written, no device test |
| M2, M3, M5 | Same sensor family (`PMU tdie`), no device test |
| macOS 14 / 15 | Build target compatible, no device test |

Sources: [exelban/stats sensor list](https://github.com/exelban/stats/blob/master/Modules/Sensors/values.swift), [vladkens/macmon](https://github.com/vladkens/macmon), [MacRumors 2026 Mac roadmap](https://www.macrumors.com/2026/07/27/mac-roadmap-2026/), [Macworld M5 Pro/Max](https://www.macworld.com/article/2942089/macbook-pro-m5-pro-max-release-specs-price.html).
