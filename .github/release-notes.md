Switching accounts now closes the tool and reopens it for you.

### The switch holds now

Codex keeps its session in memory and writes it back when it exits, so
swapping the file underneath a running Codex achieved nothing: quitting put
the old session straight back, and because refresh tokens rotate, the round
trip could leave you at a login screen.

Choosing another account now says the tool is open and offers to quit it,
switch, and reopen it. The outgoing session is saved after the tool has fully
exited, so what gets stored is the last thing it wrote rather than a copy that
is already out of date.

### Failures say what went wrong

Switching used to discard its errors, so a real failure looked exactly like a
dead button. Both the Accounts tab and Settings now show the reason, and a
saved session is checked before it replaces the live one, so a damaged copy is
reported instead of being discovered at a login prompt.

Sessions that have sat unused long enough to need a fresh sign in are marked.

### Install

Download MacInotch.zip, unzip it, move MacInotch.app to Applications. The
build is ad-hoc signed, so open it with a right click the first time, or run
`xattr -dr com.apple.quarantine /Applications/MacInotch.app`.
