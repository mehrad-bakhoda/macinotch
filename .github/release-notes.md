A coffee cup that keeps the Mac awake, and a launch hang worth fixing.

### The cup

A coffee cup sits in the quick actions row. Clicking it fills the cup, steam
rises off it, and the Mac stops going to sleep. Clicking again empties it and
normal sleep resumes.

The cup drains as the time runs down, so how full it is tells you how long is
left. Right click for a different length, from fifteen minutes to four hours,
or until you turn it off, in which case the cup simply stays full. Settings
chooses the default length and whether the display is kept on as well or only
the machine.

Sleep is held through a power assertion, the same mechanism caffeinate uses,
which is released the moment it expires, is turned off, or the app quits.

### The app could hang at launch

Reading the saved GitHub token touched the keychain on the main thread while
the application was still starting. When macOS decided to ask about keychain
access, which it does whenever the signature changes, the prompt could not be
shown yet and the launch never finished. The notch appeared to start but
nothing updated, because nothing after that point ever ran.

Keychain reads now happen off the main thread. This one was there before the
cup and would have kept happening after updates.

### Install

Download MacInotch.zip, unzip it, move MacInotch.app to Applications. The
build is ad-hoc signed, so open it with a right click the first time, or run
`xattr -dr com.apple.quarantine /Applications/MacInotch.app`.
