Real usage figures, real session names, and saved Codex accounts.

### Usage now comes from the source

Codex reports its own rate limits, so MacInotch reads them instead of
guessing: the five hour and weekly windows, the percentage used and the real
reset time. Claude Code publishes no quota anywhere on disk, so its figure is
now shown honestly as a local token tally rather than dressed up as a limit.

This also removes a wrong notification. The old code inferred a window from
message timestamps and moved its start whenever it saw activity after a gap,
which announced resets that had never happened. A reset is now only announced
when the provider says one occurred.

### Sessions

Names come from the sources themselves, so Codex sessions are no longer all
called "Codex". A session counts as live when its process is actually running,
not when its transcript happens to be recent, and the list can be narrowed to
running sessions only.

### Saved Codex accounts

Sign in with the codex CLI as usual, then save that session under a name. Save
as many as you like and switch between them from the new Accounts tab without
signing in again.

Sessions are held in the login keychain, marked accessible only when unlocked
and only on this device, so they are never synced and never written to disk in
the clear. MacInotch never sees your password and runs no login flow of its
own. Switching replaces the Codex session file through an atomic rename at
owner only permissions, and saves the outgoing session first so a switch
cannot strand an account.

### Install

Download MacInotch.zip, unzip it, move MacInotch.app to Applications. The
build is ad-hoc signed, so open it with a right click the first time, or run
`xattr -dr com.apple.quarantine /Applications/MacInotch.app`.
