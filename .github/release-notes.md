Far fewer keychain prompts, and a reply button only where a reply is wanted.

### The keychain prompts

The saved token was read from the keychain on every single API call, which
meant about ten reads every three minutes, and a prompt for each one whenever
macOS had not been told to always allow. That was careless.

It is read once now and held for as long as the app runs. Signing in does not
read it at all, since the value is already in hand. Saved account sessions are
rewritten only when the credential has actually changed rather than whenever
the file is touched, and the tools rewrite that file on every token refresh.

The prompt itself comes from the ad-hoc signature changing with each build, so
macOS treats every version as a new application. Always Allow settles it for a
given version.

### Reply where it belongs

A reply button on a receipt is noise. It now appears only on messages sorted as
needing you or wanting an answer. Anything filed as information or marketing
offers only mark as read, with reply still available from the right click menu
for the times the sorting is wrong.

### Install

Download MacInotch.zip, unzip it, move MacInotch.app to Applications. The
build is ad-hoc signed, so open it with a right click the first time, or run
`xattr -dr com.apple.quarantine /Applications/MacInotch.app`.
