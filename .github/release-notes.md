Account switching works again, and the site shows what the app actually does.

### Switching was giving up too early

Waiting for the tool to close asked the wrong question. It checked whether any
process named codex was running, over and over, and the host application spawns
fresh helpers as it shuts down and comes back, so that answer never became no.
The switch was abandoned, the app reopened, and the previous account was still
signed in. The message said it could not close, while it plainly had.

It now waits for the exact processes it asked to quit, and stops waiting once
those are gone rather than once the name disappears from the system.

### Screenshots

The site was still showing four screens from an app that has gained mail,
accounts, GitHub, a quick actions row and a coffee cup since. It now shows
seven, captured from a demo mode that fills the panel with invented mail,
accounts and repositories, so no real inbox or account appears on a public page.

### Install

Download MacInotch.zip, unzip it, move MacInotch.app to Applications. The
build is ad-hoc signed, so open it with a right click the first time, or run
`xattr -dr com.apple.quarantine /Applications/MacInotch.app`.
