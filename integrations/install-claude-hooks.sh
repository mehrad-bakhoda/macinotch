#!/bin/bash
# Merges the MacInotch hooks into ~/.claude/settings.json (backing up first).
set -euo pipefail
SETTINGS="$HOME/.claude/settings.json"
SNIPPET="$(dirname "$0")/claude-code-hooks.json"

mkdir -p "$(dirname "$SETTINGS")"
[ -f "$SETTINGS" ] || echo '{}' > "$SETTINGS"
cp "$SETTINGS" "$SETTINGS.macinotch-backup.$(date +%s)"

python3 - "$SETTINGS" "$SNIPPET" <<'PY'
import json, sys
settings_path, snippet_path = sys.argv[1], sys.argv[2]
settings = json.load(open(settings_path))
snippet = json.load(open(snippet_path))

hooks = settings.setdefault("hooks", {})
for event, entries in snippet["hooks"].items():
    existing = hooks.setdefault(event, [])
    # Drop any previous MacInotch entries so re-running stays idempotent.
    existing[:] = [e for e in existing
                   if "notchctl" not in json.dumps(e)]
    existing.extend(entries)

json.dump(settings, open(settings_path, "w"), indent=2)
print("updated", settings_path)
PY

echo "Backup written next to settings.json. Restart Claude Code to pick the hooks up."
