# MacInotch

Turn the notch on a MacBook into something useful.

MacInotch grows the camera housing into a live status readout, a notification
surface, a file shelf and a media controller. It sits above the menu bar,
collapsed and quiet until it has something to say, and expands when you hover
it.

Built with SwiftUI and AppKit. No Xcode project, it compiles with the Command
Line Tools alone.

---

## Features

### Always visible

The collapsed notch shows whatever you choose from fourteen items, CPU,
memory, SoC temperature, weather, battery, disk, network, clock, Shamsi date,
Gregorian date, uptime, app presence, now playing, and a timer. Pick what sits
on each side; the notch resizes to fit and hides anything that has no data.

### On hover

| | |
|---|---|
| **Clock and calendars** | Gregorian, Shamsi (Jalali, in Farsi with Persian numerals) and Hijri, plus week number, day-of-year progress and a Nowruz countdown |
| **Vitals** | CPU, memory, temperature, fan speed, power draw, battery, disk and network in one card, with 60-sample sparklines and the process responsible for each spike |
| **Weather** | Current conditions, high and low, from Open-Meteo |
| **Media** | Spotify and Apple Music with artwork, scrubbing, transport and volume |
| **Calendar** | Next event with a countdown and a join button for Zoom, Meet, Teams, Webex, Whereby, Around and Jitsi |
| **AI usage** | Token counts for Claude Code and Codex in a rolling window, with a chime when it resets |
| **Activity** | Recent notifications with optional action buttons |

### Tabs

- **Dock**, a file shelf and clipboard history. Drag files onto the notch to
  park them, then drag them straight back out. Named piles keep work separate.
  New screenshots land here automatically.
- **Sessions**, recent Claude Code and Codex sessions per project, with
  message counts, token spend and a live indicator.
- **Notes**, sticky notes backed by plain `.md` files in a folder you choose.

### Other

- Fan monitoring, and timed boost presets through an optional root helper
- Pomodoro and plain timers, drawn as a ring tracing the notch outline
- Menu bar item hiding, with no Accessibility permission required
- Bluetooth device battery, audio output switching
- Notification history, searchable and persistent
- Light and dark themes, Liquid Glass on macOS 26+, six opening animations

---

## Install

### Download

Grab the latest `.app` from
[Releases](https://github.com/mehrad-bakhoda/macinotch/releases), move it to
`/Applications`, and open it.

The build is ad-hoc signed, so the first launch needs a right-click → **Open**,
or:

```bash
xattr -dr com.apple.quarantine /Applications/MacInotch.app
```

### Build from source

Requires macOS 14 or later and the Xcode Command Line Tools.

```bash
git clone https://github.com/mehrad-bakhoda/macinotch.git
cd macinotch
./scripts/build.sh
open build/MacInotch.app
```

`build.sh` compiles in release mode, assembles the app bundle, signs it ad-hoc,
and symlinks the `notchctl` CLI into `~/.local/bin`.

MacInotch runs as a menu-bar accessory with no Dock icon. Its menu-bar icon
opens Settings, sends a test notification, mutes, and pins the panel.

---

## Sending notifications

### notchctl

```bash
notchctl "Build finished" "42 tests passed" -s claude -k success
notchctl "Reply ready" -s chatgpt
```

Kinds: `info` `success` `warning` `error` `progress` `attention` `music`.
Sources: `claude` `chatgpt` `spotify` `system` `custom`, they choose the badge
and colour.

**Progress that updates in place.** Reuse a `--key` and the same item is
updated rather than stacked:

```bash
notchctl --key deploy --progress 0.4 --title "Deploying"
notchctl --key deploy --progress 0.9 --title "Deploying"
notchctl --dismiss deploy
```

**Attention.** `--kind attention` is sticky: the notch pulses and stays that
way until you hover it.

```bash
notchctl --key review --kind attention --title "Approve the release?"
```

**Watch a command.** Pipe any long-running command through the notch. Output
still passes through, so the command behaves normally:

```bash
swift build 2>&1 | notchctl watch --title "Compiling" -s claude
```

**Fans.**

```bash
notchctl fan              # current speeds
notchctl fan blast 5      # full speed for five minutes
notchctl fan 50 10        # half speed for ten minutes
notchctl fan auto         # hand control back to macOS
```

### HTTP

A loopback-only endpoint on port 9977. Nothing off the machine can reach it.

```bash
curl -s localhost:9977/notify -d '{"source":"claude","title":"Done","kind":"success"}'
curl -s localhost:9977/state  | jq     # vitals, temps, presence, dates, usage
curl -s localhost:9977/prefs  | jq     # every setting
curl -s localhost:9977/prefs  -d '{"appearance":"light"}'
curl -s localhost:9977/fan    -d '{"percent":1.0,"minutes":5}'
curl -s localhost:9977/health
```

`POST /prefs` patches only the keys you send, so scripts can change one setting
without touching the rest.

Notifications can carry action buttons:

```bash
curl -s localhost:9977/notify -d '{
  "title":"Deploy ready","kind":"attention","source":"claude",
  "actions":[{"label":"Open logs","url":"https://example.com"},
             {"label":"Retry","command":"make deploy"}]
}'
```

### URL scheme

For Shortcuts, Raycast, Stream Deck, or anything that can open a URL:

```
macinotch://notify?title=Hello&kind=success&source=claude
macinotch://timer?minutes=25
macinotch://timer?pomodoro=1
macinotch://fan?percent=1.0&minutes=5
macinotch://menubar
macinotch://pin
macinotch://mute?minutes=60
macinotch://settings
```

---

## Integrations

### Claude Code

Get a pulsing notch when Claude Code needs input and a chime when it finishes:

```bash
./integrations/install-claude-hooks.sh
```

This merges `integrations/claude-code-hooks.json` into
`~/.claude/settings.json`, backing the file up first. It is safe to re-run.
Restart Claude Code afterwards.

### Notification Center

Settings → Connect can mirror real macOS notifications into the notch by
tailing the `usernoted` database. This is how apps without a hook API get in.
It needs Full Disk Access, and can be limited to specific bundle identifiers.

### Config file

Settings can be pinned from `~/.config/macinotch/config.json`, merged over your
saved preferences at launch. A dotfile only needs to name the keys it cares
about:

```json
{
  "appearance": "dark",
  "openAnimation": "snappy",
  "idleLeft": ["cpu", "ram", "weather"],
  "idleRight": ["music", "presence"]
}
```

Settings → Connect can export your current settings into that file.

---

## Permissions

Everything is optional. MacInotch works without any of it, and the first-run
setup guide walks through each one.

| Feature | Requires |
|---|---|
| Now playing | Automation access to Spotify or Music |
| Weather | Location, or manual coordinates in Settings |
| Calendar | Calendar access |
| Notification mirror, Focus awareness | Full Disk Access |
| Fan control | An administrator password once, to install the helper |
| Everything else | Nothing |

---

## Fans

Settings → Fans shows live RPM per fan and offers 50%, 75% and full speed for
2 to 30 minutes. Control needs a small root helper, because macOS refuses SMC
writes from ordinary applications. Installing it asks for an administrator
password once.

The safety rules live in the daemon rather than the interface:

- targets are clamped to the fan's own reported range
- every override carries a deadline, capped at one hour
- overrides are re-asserted every two seconds, because macOS rewrites the
  target itself
- it reverts to automatic on expiry, on exit, or above 90 °C

There is no "off". The slowest speed the SMC accepts is the fan's reported
minimum; the firmware still stops the fans on its own when the machine is cool.

Fan control depends on the SMC accepting writes, which varies by model. If it
refuses, the interface says so rather than silently doing nothing.

---

## Architecture

```
Sources/
  MacInotch/
    Core/       state, preferences, theme, window placement, models
    Services/   music, battery, CPU and memory, temperature, fans, presence,
                weather, calendar, clipboard, shelf, notes, sessions, timers,
                notifications, HTTP server
    Views/      notch shape, collapsed strip, banner, panel, settings
    Util/       calendars, sounds, icons, hotkey, login item
  SMCKit/       shared SMC client, used by the app and the root helper
  notchctl/     command line interface
  notchfand/    privileged fan helper
scripts/        build, icon generation, sound synthesis
integrations/   Claude Code hooks
docs/           project website
```

### Notes on the implementation

The source carries no comments, so the parts that are genuinely surprising are
recorded here.

**The SMC request struct is 80 bytes with C padding Swift does not reproduce.**
A Swift struct mirroring `SMCKeyData_t` field for field measures 76 bytes and
every call silently returns nothing. `SMCKit` builds requests as a raw byte
buffer at explicit offsets.

**Swift's synthesised `Codable` fails outright on a missing key.** Decoding the
preferences struct directly would discard every setting whenever a new
preference is added, so stored JSON is merged onto a default instance instead.

**`MainActor.assumeIsolated` traps off the main thread.** Background services
cannot reach main-actor state directly; anything they need is mirrored behind a
lock.

**macOS drives the fans in forced mode itself.** `F<i>Md` reads 1 during normal
thermal management, and macOS rewrites `F<i>Tg` continuously, so a one-shot
write is overwritten within about two seconds.

**Apple Silicon thermal sensors have no public API.** Temperatures come from
`IOHIDEventSystem` calls resolved at runtime. `PMU tcal` is a calibration
reference reading about 12 °C high and is excluded.

**Battery capacity is nested.** The top-level `MaxCapacity` is a percentage;
the real figures live in the `BatteryData` dictionary.

**Menu bar hiding needs no Accessibility permission.** macOS honours an
oversized `NSStatusItem`, so a wide item pushes everything to its left off
screen. Listing other apps' status items is a different matter, the menu bar
is a single composited surface, so that would need Screen Recording.

**Sounds and the app icon are generated, not drawn.** `scripts/make_sounds.py`
synthesises the notification tones and `scripts/make_icon.swift` renders the
icon; both are re-runnable.

---

## Website

The project site lives in `web/`, a Next.js app exported as static files and
published to GitHub Pages by `.github/workflows/pages.yml`.

```bash
cd web
npm install
npm run dev
```

Screenshots on the site come from `scripts/capture-shots.sh`. Run it with a
clear screen, since the panel is translucent and whatever sits behind it shows
through. Review every file it writes before committing.

## Contributing

Issues and pull requests are welcome.

```bash
swift build                 # debug
./scripts/build.sh          # release bundle
python3 scripts/strip_comments.py
```

The codebase keeps no comments; anything worth explaining goes in this file.
Match the surrounding style, small focused types, services that publish into
`NotchState`, and views that read from it.

---

## Licence

MIT. See [LICENSE](LICENSE).

Copyright © 2026 Mehrad Bakhoda.
