#!/usr/bin/env bash
# S8 (adversarial): the throwaway sibling is what makes a last-in-window close
# work at all. When cmux refuses to create it, the close would be the
# documented silent no-op - so the failure must be reported and the workspace
# preserved, never closed into and called a removal.
set -u
ROOT=$1
. "$ROOT/bin/fm-backend.sh"; fm_backend_source cmux
LABEL=fm-test-nosibling
TITLE=$(fm_backend_cmux_scoped_title "$LABEL")
WIN_B=""
cleanup() { [ -z "$WIN_B" ] || fm_backend_cmux_cli close-window --window "$WIN_B" >/dev/null 2>&1; }
trap cleanup EXIT
show_window() { fm_backend_cmux_cli workspace list --json --id-format both --window "$1" 2>/dev/null | jq -r '.workspaces[]? | "    \(.ref)\t\(.title)"'; }

WIN_B=$(fm_backend_cmux_cli new-window 2>&1 | awk '{print $2}')
[ -n "$WIN_B" ] || { echo "ABORT: could not open a throwaway window"; exit 2; }
sleep 1.5
RAW=$(fm_backend_cmux_cli new-workspace --name "$TITLE" --cwd /tmp --focus false --window "$WIN_B" --id-format uuids 2>&1)
REF=$(fm_backend_cmux_created_workspace_ref "$RAW")
[ -n "$REF" ] || { echo "ABORT: new-workspace returned no ref ([$RAW])"; exit 2; }
sleep 1.5
SEED=$(fm_backend_cmux_cli workspace list --json --id-format both --window "$WIN_B" 2>/dev/null | jq -r --arg r "$REF" '.workspaces[]? | select(.ref != $r) | .ref' | head -1)
[ -n "$SEED" ] && fm_backend_cmux_cli close-workspace --workspace "$SEED" >/dev/null 2>&1
sleep 1.5
echo "window B holds only the partial workspace $REF:"; show_window "$WIN_B"

echo
echo "--- cleanup while cmux refuses to create the throwaway sibling ---"
export FM_FAULT=sibling-fails
set +e
out=$(fm_backend_cmux_close_created_workspace "$REF" "$TITLE" 2>&1); st=$?
set -e
unset FM_FAULT
echo "  status: $st (non-zero = did not claim a removal)"
echo "  message: $out"
sleep 1
echo "  window B afterwards:"; show_window "$WIN_B"
STILL=$(fm_backend_cmux_cli workspace list --json --id-format both --window "$WIN_B" 2>/dev/null | jq -r --arg r "$REF" '.workspaces[]?|select(.ref==$r)|.ref')
case "$out" in
  *"could not close the partial workspace"*) echo "  OK: the failed sibling create was reported, not swallowed" ;;
  *"removed the partial workspace"*) echo "  FAIL: claimed a removal the failed sibling made impossible" ;;
  *) echo "  FAIL: unexpected message" ;;
esac
[ -n "$STILL" ] && echo "  OK: the workspace is preserved, exactly as the operator was told" || echo "  NOTE: workspace is gone"
