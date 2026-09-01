The notch now watches the machine, your calendar, and your repositories.

### It tells you when something is wrong

The vitals were already sampled every few seconds and thrown away. Now a disk
filling up, a process pinning a core for two minutes, thermal throttling, and
a failing battery each warn once, and rearm only after the condition clears.

Network state is new. The path monitor reports whether a connection is metered
or constrained, which is what you want to know before starting a large
download, and connected VPNs are read from the system configuration.

### Meetings

The calendar now lists today's events and your open reminders, which needs the
separate reminders permission. When an event with a join link starts, the
notch offers to join it or to go quiet for its duration.

Meeting mode mutes system audio and holds notifications until the event ends,
then puts both back. It leaves audio alone if it was already muted, so it
cannot unmute something you silenced yourself. It is offered once per event
rather than imposed.

### GitHub

Connect a personal access token and the notch shows today's pushes, pull
requests you opened, and reviews waiting on you. A failing workflow raises a
notification with a link to the run.

The token goes straight into your keychain, marked for this device only. It is
never written to disk, never leaves the machine except to api.github.com, and
never appears on the local endpoint.

### Focus and recording

Focus state was already read from the system but only shown as a dot. It is
now a row naming the mode, and tapping it runs a Shortcut you choose, because
macOS lets you observe a Focus but not set one.

Screen recordings already landed in the shelf once they existed. Starting one
is now a button in the Dock tab that shows elapsed time and files the result.

### Install

Download MacInotch.zip, unzip it, move MacInotch.app to Applications. The
build is ad-hoc signed, so open it with a right click the first time, or run
`xattr -dr com.apple.quarantine /Applications/MacInotch.app`.
