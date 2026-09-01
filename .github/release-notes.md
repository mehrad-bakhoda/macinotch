Quick actions and connecting accounts, without opening Settings.

### A row of actions in the panel

Meeting mode, holding notifications, Focus, and screen recording are now
buttons at the top of the panel. Each lights up when it is on and turns off
with the same click, so going quiet for a call and coming back out of it is
two taps in the place you were already looking.

### Connecting is one click

The calendar and GitHub buttons sit in the same row and show whether they are
connected. Tapping the calendar asks macOS for access. Google, Exchange and
other calendars come from the accounts already on the machine, so the button's
menu opens Internet Accounts to add one.

Tapping GitHub opens a field to paste a token, with a link to the page that
creates one. The panel pins itself while the field is open so it cannot
collapse mid paste.

### Where the token goes

Straight into your login keychain, marked accessible only when unlocked and
only on this device. It is never synced, never written to preferences or any
file, never printed, and never appears on the local endpoint. The field is a
secure one and is cleared the moment it is used. Requests go to api.github.com
and nowhere else. Connecting again after a restart is not necessary; the
keychain entry is read at launch.

### Install

Download MacInotch.zip, unzip it, move MacInotch.app to Applications. The
build is ad-hoc signed, so open it with a right click the first time, or run
`xattr -dr com.apple.quarantine /Applications/MacInotch.app`.
