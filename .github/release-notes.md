Declining calendar access is no longer a dead end.

macOS asks for a permission exactly once. After Don't Allow, asking again
returns immediately with no dialog, so the connect button appeared to do
nothing at all. There was no way to tell from the app that the answer had
already been given and could not be asked for again.

The button now reads Open Privacy Settings when access has been declined and
goes there instead of requesting something macOS will not present. Settings
explains what happened and offers the tccutil command that clears the decision
so the prompt can appear again, ready to copy.

The panel's calendar icon carries the same explanation in its tooltip.

### Install

Download MacInotch.zip, unzip it, move MacInotch.app to Applications. The
build is ad-hoc signed, so open it with a right click the first time, or run
`xattr -dr com.apple.quarantine /Applications/MacInotch.app`.
