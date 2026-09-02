The Codex figure was showing the wrong limit, and saying so too often.

### It was reading someone else's number

Codex writes several kinds of rate limit, each tagged with a limit id. Your plan
limit is one of them; others cover separate pools entirely. The code took
whichever record was written most recently and believed it, so a reserve pool
sitting at zero on a seven day window replaced the plan limit that was actually
constraining you. What it showed was real data about the wrong thing.

The plan limit is now picked out by name, and the five hour and weekly windows
come from that record alone.

### It announced a reset every few minutes

That reserve window rolls forward continuously, a minute or two at a time, and
a reset was declared whenever the reset time moved at all. Moving forward is
what a rolling window does. A reset is now only called when the window rolls
over by at least half its length and usage actually falls, which is what a
reset looks like from outside.

### Claude Code limits

Claude Code has started recording its own limits, so its row can show when a
five hour or weekly window is spent and when it comes back, rather than only a
token tally. The tally remains until there is a limit to show.

### Install

Download MacInotch.zip, unzip it, move MacInotch.app to Applications. The
build is ad-hoc signed, so open it with a right click the first time, or run
`xattr -dr com.apple.quarantine /Applications/MacInotch.app`.
