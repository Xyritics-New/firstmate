#!/usr/bin/env bash
# S0: the live cmux CLI contract this whole change rests on -
#   new-workspace returns "OK workspace:<n>", `workspace list --id-format both`
#   maps that ref to the uuid, and close-workspace accepts the ref directly.
set -u
ROOT=$1
. "$ROOT/bin/fm-backend.sh"; fm_backend_source cmux
. "$ROOT/tests/cmux-test-safety.sh"

LABEL=fm-test-refprobe
TITLE=$(fm_backend_cmux_scoped_title "$LABEL")
echo "scoped title: $TITLE"

RAW=$(fm_backend_cmux_cli new-workspace --name "$TITLE" --cwd /tmp --focus false --id-format uuids 2>&1)
echo "new-workspace raw stdout: [$RAW]"
REF=$(fm_backend_cmux_created_workspace_ref "$RAW")
echo "parsed ref: [$REF]"
[ -n "$REF" ] || { echo "FAIL: no ref parsed"; exit 1; }

UUID=$(fm_backend_cmux_workspace_id_for_ref "$REF")
echo "ref -> uuid via 'workspace list --id-format both': [$UUID]"
[ -n "$UUID" ] || { echo "FAIL: ref did not resolve to a uuid"; exit 1; }

echo "window walk for the ref: [$(fm_backend_cmux_window_of_workspace "$REF")]"
echo "window walk for the uuid: [$(fm_backend_cmux_window_of_workspace "$UUID")]"

echo "--- closing by the REF alone (no uuid, no title) ---"
if fm_backend_cmux_close_created_workspace "$REF" "$TITLE"; then
  echo "close_created_workspace: reported removal"
else
  echo "close_created_workspace: refused to report removal (status $?)"
fi
LIVE=$(fm_backend_cmux_cli workspace list --json --id-format both 2>/dev/null | jq -r --arg t "$TITLE" '.workspaces[]? | select(.title == $t) | .ref')
echo "workspaces still carrying the title after close: [${LIVE:-<none>}]"
[ -z "$LIVE" ] || { echo "FAIL: workspace survived"; cmux_safe_close_workspace "$UUID" "$LABEL"; exit 1; }
echo "PASS: new-workspace's ref is a closable handle for exactly what it created"
