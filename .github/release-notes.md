A disk image, so installing is a drag rather than a chore.

### Installing

Releases now carry MacInotch.dmg. Opening it shows the application beside a
shortcut to Applications, with an arrow between them, which is how every other
Mac application asks to be installed. Dragging it across is the whole procedure.

The window layout travels with the image rather than being arranged by scripting
Finder during the build, because the machine that builds it has no one logged in
to arrange anything. The zip is still attached for anyone who prefers it.

The download button on the site now fetches the disk image directly instead of
sending you to a releases page to find it.

### Before that

Everything was checked rather than assumed: every endpoint, the command line
tool, the URL scheme, the sounds, the timer, notifications, and that no
credential appears on the local endpoint. Twenty eight checks, all passing. The
three that failed at first were the test reading a snapshot that is now
deliberately three seconds stale while the panel is closed, not the application.

### Install

Open MacInotch.dmg, drag MacInotch into Applications, then open it from there
with a right click the first time. Or run
`xattr -dr com.apple.quarantine /Applications/MacInotch.app`.
