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
| **AI usage** | Codex limits as Codex itself reports them, five hour and weekly, with the pace you are burning them and when you will run out. Warns at 80% and 95%, and offers another saved account when one has room. Claude Code publishes no quota, so it shows a local token tally instead |
| **Meetings** | Today's events and open reminders, with a join button and an offer to mute audio and hold notifications for the duration |
| **GitHub** | Today's pushes, pull requests opened and reviews waiting on you, with a notification when a workflow fails |
| **Network** | Wi-Fi, VPN, and whether the connection is metered before you start a large download |
| **Activity** | Recent notifications with optional action buttons |

### Signing in to GitHub

MacInotch supports GitHub's device flow, so signing in opens a browser, shows
a code, and waits for you to approve it. Nothing is typed into the app and
there is no client secret. A personal access token works too, for anyone who
would rather make one by hand. Either way the credential is kept in the login
keychain, marked for this device only, and never written to disk.

The endpoints used are the authenticated user, your own event feed, a search
for pull requests awaiting your review, and workflow runs for the repositories
you have been active in. A fine grained token therefore needs Metadata,
Contents, Pull requests and Actions, all read only.

### Quick actions

A row of buttons at the top of the panel toggles meeting mode, holds
notifications, switches Focus, starts a screen recording, and keeps the Mac
awake behind a coffee cup that fills and steams while it holds sleep off,
draining as the time runs down. The same row
connects your calendar and GitHub, so neither needs a trip to Settings.

### Tabs

- **Dock**, a file shelf and clipboard history. Drag files onto the notch to
  park them, then drag them straight back out. Named piles keep work separate.
  New screenshots land here automatically.
- **GitHub**, today's pushes, pull requests and reviews waiting on you, a
  contribution graph and any failing workflows.
- **Sessions**, Claude Code and Codex sessions with their real names, message
  counts, token spend and a live indicator driven by whether the process is
  actually running. Can be narrowed to running sessions only, and clicking one
  resumes that conversation.
- **Notes**, sticky notes backed by plain `.md` files in a folder you choose.

### Other

- Fan monitoring, and timed boost presets through an optional root helper
- Pomodoro and plain timers, drawn as a ring tracing the notch outline
- Menu bar item hiding, with no Accessibility permission required
- Several Codex and Claude Code accounts saved in the keychain, switched from the
  Accounts tab without signing in again. Switching closes the tool and reopens
  it, because it writes its session back on exit and would otherwise undo the
  swap
- Bluetooth device battery, audio output switching
- Warnings for a filling disk, a runaway process, throttling and battery health
- Screen recording started from the shelf, with the file parked there when done
- Focus state in the panel, toggled through a Shortcut you choose
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
swift build -c release
```

That produces three binaries in `.build/release`: `MacInotch`, the `notchctl`
CLI, and the `notchfand` fan helper. Put `notchctl` somewhere on your `PATH`.

A packaged `MacInotch.app` is produced by CI on every push and attached to each
release, so the quickest way to get the bundle is to download it.

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
curl -s localhost:9977/caffeine -d '{"minutes":60}'
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
macinotch://caffeine?minutes=60
macinotch://caffeine?off=1
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
| Reminders | Reminders access |
| Fan control | An administrator password once, to install the helper |
| Saved accounts | Keychain access, granted on first use |
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

**Only Codex reports its own limits.** Codex writes a `rate_limits` record
into its rollout transcripts carrying `used_percent`, `window_minutes` and
`resets_at` for a five hour and a weekly window, so those figures are exact.
Claude Code writes no quota, reset or limit field anywhere under `~/.claude`,
so its usage is counted locally from transcripts and presented as a tally
rather than a limit. Inferring a window from message timestamps was worse than
useless, it announced resets that had not happened.

**A Codex rollout opens with a very large record.** The `session_meta` line
carrying `cwd` runs to tens of kilobytes, so a short read truncates it, the
parse fails and the session appears unnamed. Names otherwise come from
`thread_name` in `~/.codex/session_index.jsonl`, and for Claude from the `name`
field in `~/.claude/sessions`.

**A recently written transcript does not mean a running session.** Liveness is
a live pid for Claude Code and a running `codex` process for Codex.

**macOS lets you observe a Focus but not set one.** There is no public
interface for changing Focus, so toggling runs a Shortcut you nominate. Reading
the current state stays exact, since that comes from the assertion store.

**Metered connections are a network path property, not a Wi-Fi name.** Personal
hotspots cannot be recognised reliably by SSID, but the path monitor reports
`isExpensive` and `isConstrained`, which is the thing actually worth acting on.
Wi-Fi names need Location, so the label falls back to the interface without it.

**Codex rollouts do not say which account wrote them.** They carry a rate
limit on every turn but no account identity, so a measurement cannot be
attributed by reading it. Anything measured before the most recent account
switch is ignored instead, which is the only reliable way to keep two accounts
apart from files that do not distinguish them.

**A declined permission cannot be asked for twice.** macOS presents each
request once, and afterwards the call returns immediately with no dialog, which
is indistinguishable from a button that does nothing. Anywhere access can be
declined, the interface has to notice and send the reader to the privacy pane
instead of asking again.

**The keychain can block the main thread.** Reading a saved credential during
launch is enough to hang the application outright: if macOS decides to ask
about keychain access, the prompt cannot be presented while the app is still
starting, and the launch never completes. Keychain work belongs off the main
thread.

**Battery capacity is nested.** The top-level `MaxCapacity` is a percentage;
the real figures live in the `BatteryData` dictionary.

**Menu bar hiding needs no Accessibility permission.** macOS honours an
oversized `NSStatusItem`, so a wide item pushes everything to its left off
screen. Listing other apps' status items is a different matter, the menu bar
is a single composited surface, so that would need Screen Recording.

**Sounds and the app icon are generated rather than drawn.** The notification
tones are synthesised mallet hits, and the icon is rendered from a superellipse
with the notch silhouette bitten out of it. Both ship in `Resources`.

---

## Website

The project site lives in `web/`, a Next.js app exported as static files and
published to GitHub Pages by `.github/workflows/pages.yml`.

```bash
cd web
npm install
npm run dev
```

Screenshots live in `web/public/shots`. Capture them with the glass turned off
so the panel is opaque, cropped to the panel bounds, otherwise whatever is
behind the panel shows through.

## Contributing

Issues and pull requests are welcome.

```bash
swift build                 # debug
swift build -c release      # release
```

The codebase keeps no comments; anything worth explaining goes in this file.
Match the surrounding style, small focused types, services that publish into
`NotchState`, and views that read from it.

---

## Licence

MIT. See [LICENSE](LICENSE).

Copyright © 2026 Mehrad Bakhoda.
