#!/usr/bin/env bash
# S9 (adversarial): the window walk that would prove removal cannot be
# completed, and cmux's close removed nothing. "I could not confirm" must be
# what the operator is told - never "removed".
set -u
ROOT=$1
. "$ROOT/bin/fm-backend.sh"; fm_backend_source cmux
LABEL=fm-test-unconfirmed
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
echo "partial workspace $REF in throwaway window B:"; show_window "$WIN_B"

echo
echo "--- cmux's close removes nothing AND the confirming window walk cannot be read ---"
export FM_FAULT=close-workspace-noop,list-windows-fails
set +e
out=$(fm_backend_cmux_close_created_workspace "$REF" "$TITLE" 2>&1); st=$?
set -e
unset FM_FAULT
echo "  status: $st (non-zero = did not claim a removal)"
echo "  message: $out"
case "$out" in
  *"could not confirm removal"*) echo "  OK: said removal was unproven rather than asserting it" ;;
  *"removed the partial workspace"*) echo "  FAIL: claimed a removal it could not confirm" ;;
  *) echo "  FAIL: unexpected message" ;;
esac
sleep 1
echo "  window B afterwards (the workspace really is still there):"; show_window "$WIN_B"
