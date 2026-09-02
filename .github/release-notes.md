The disk image reads properly now.

Finder draws the icon names in a disk image window itself, in a dark colour,
and no setting in the image can change that. On the previous dark background
they were nearly invisible. The background is light now, which is what almost
every Mac application ships for exactly this reason, and the names read as they
are supposed to.

The notch silhouette stays at the top so the window is recognisably this
application, and the instruction underneath now mentions the right click needed
on first open.

### Install

Open MacInotch.dmg, drag MacInotch into Applications, then open it from there
with a right click the first time. Or run
`xattr -dr com.apple.quarantine /Applications/MacInotch.app`.
