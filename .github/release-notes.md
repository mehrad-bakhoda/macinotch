Unread mail in the notch, summarised on device, with a reply box.

### Mail

A Mail tab lists what is unread from the last day, newest first, with the
sender, the subject and how long ago it landed. Flagged messages are marked.
New mail raises a notification, flagged mail more insistently.

Each message carries a one sentence summary written by the language model
built into macOS. It runs on the machine, so no mail is sent anywhere, no
account is involved and no key is needed. Where Apple Intelligence is not
available the summary falls back to the opening lines of the message.

Replies are written in the panel and sent through Mail. Nothing is ever sent
without pressing send.

### How it reads your mail

Through Mail itself, so your accounts stay where macOS keeps them and this app
holds no mail credentials, no password and no token of its own. It needs the
account added in Internet Accounts, the same place calendars come from, and
Mail running, since it reads what Mail already has rather than talking to a
mail server. The tab says which of those is missing rather than sitting empty.

### Install

Download MacInotch.zip, unzip it, move MacInotch.app to Applications. The
build is ad-hoc signed, so open it with a right click the first time, or run
`xattr -dr com.apple.quarantine /Applications/MacInotch.app`.
