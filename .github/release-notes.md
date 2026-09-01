Usage attributed to the right account, a GitHub tab, and choosing calendars.

### The wrong account was being credited

Codex rollout files record a rate limit on every turn but never say which
account produced it. The newest measurement was therefore stamped onto
whichever account happened to be signed in when it was read, so switching
accounts moved the previous account's figure onto the new one, or the reverse.
An account sitting at zero could show a hundred.

Measurements taken before the most recent switch are now ignored, which is the
only honest way to tell the two apart from files that do not distinguish them.
Readings stored by earlier versions cannot be trusted and are discarded once on
upgrade, so figures start empty and refill as they are measured. A single
reading can also be cleared from the account's menu.

### Knowing when a parked account comes back

Each saved account keeps its own reset time, shown alongside its percentage. An
account you are not signed in to raises a notification when its window passes
that time, offering to switch to it, since the useful moment for a second
account is the moment it becomes usable again.

### A GitHub tab

Pushes, pull requests opened and reviews waiting, a contribution graph for the
last six months, and any failing workflows, with sign out alongside them.

### Choosing calendars

Every calendar the machine knows about is listed, Google and Exchange included,
each one switchable. Events are read only from the ones left on. Signing out
turns them all off and opens the privacy pane, since macOS does not allow an
application to withdraw its own permission.

### Install

Download MacInotch.zip, unzip it, move MacInotch.app to Applications. The
build is ad-hoc signed, so open it with a right click the first time, or run
`xattr -dr com.apple.quarantine /Applications/MacInotch.app`.
