Limits that warn you before you hit them, and an account that can take over.

### It tells you before you run out

Codex writes a rate limit record on every turn, so there is a real series of
measurements sitting in the rollout files rather than a single number. That is
enough to know how fast you are burning through a window, so the usage row now
reads "5h limit, resets in 3h 12m, at this pace full around 16:40".

A chime and a notification arrive at 80% and 95% of the window, once each per
window, with the reset time and the pace.

### The warning can hand over to another account

If another saved account has room, the warning offers to switch to it and says
what it knows: "rinetech is 12% as of 2h ago". Tapping it opens the Accounts
tab with the switch ready to confirm, so quitting the tool is still your
decision rather than something that happens mid task.

An account whose window has passed its reset time is reported as reset, since
that much can be worked out without being signed in to it.

### Usage is now attributed per account

Each saved account carries its own last known percentage and reset time, so
the figures no longer blend two accounts together after a switch.

### Resume a session

Clicking a session in the Sessions tab reopens that conversation in a terminal
at the project directory, rather than only revealing the transcript file. It
uses the tool's own resume command, and falls back to revealing the file when
the tool cannot be found.

### Install

Download MacInotch.zip, unzip it, move MacInotch.app to Applications. The
build is ad-hoc signed, so open it with a right click the first time, or run
`xattr -dr com.apple.quarantine /Applications/MacInotch.app`.
