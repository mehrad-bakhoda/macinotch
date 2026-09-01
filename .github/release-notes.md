Sign in to GitHub with a click, instead of making a token by hand.

### Signing in

GitHub's device flow is now supported. Pressing sign in opens github.com,
shows a short code that is already on your clipboard, and waits. Approving it
in the browser finishes the sign in. Nothing is typed into MacInotch, and no
client secret exists to leak, which is the point of that flow.

The resulting token goes into the login keychain, marked accessible only when
unlocked and only on this device, and is read back at launch so signing in
happens once.

Device flow needs a client id, which is a public identifier rather than a
secret. Until one is set the button explains the one time setup, and pasting a
personal access token still works for anyone who prefers it.

### A fix worth knowing about

A copy of the application was being left in the build directory next to the
installed one. Both carried the same identifier, so macOS could launch either,
and permissions such as calendar access are granted per application rather
than per name. Granting access to one and running the other looked exactly
like a permission that would not stick. The stray copy is gone and the build
directory is ignored.

### Install

Download MacInotch.zip, unzip it, move MacInotch.app to Applications. The
build is ad-hoc signed, so open it with a right click the first time, or run
`xattr -dr com.apple.quarantine /Applications/MacInotch.app`.
