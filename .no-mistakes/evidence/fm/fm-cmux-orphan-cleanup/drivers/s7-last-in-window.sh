#!/usr/bin/env bash
# S7 (the documented cmux trap, driven live in a throwaway window): cmux
# refuses to remove the only workspace in a macOS window and answers OK anyway.
# A partial workspace that ends up last in its window must therefore still be
# removed - via the throwaway sibling - and only then reported as removed.
set -u
ROOT=$1
. "$ROOT/bin/fm-backend.sh"; fm_backend_source cmux
LABEL=fm-test-lastin
TITLE=$(fm_backend_cmux_scoped_title "$LABEL")
WIN_B=""
cleanup() { [ -z "$WIN_B" ] || fm_backend_cmux_cli close-window --window "$WIN_B" >/dev/null 2>&1; }
trap cleanup EXIT

show_window() {  # <win>
  fm_backend_cmux_cli workspace list --json --id-format both --window "$1" 2>/dev/null \
    | jq -r '.workspaces[]? | "    \(.ref)\t\(.title)"'
}

WIN_B=$(fm_backend_cmux_cli new-window 2>&1 | awk '{print $2}')
[ -n "$WIN_B" ] || { echo "ABORT: could not open a throwaway window"; exit 2; }
sleep 1.5
echo "throwaway window B: $WIN_B"
echo "  contents:"; show_window "$WIN_B"

RAW=$(fm_backend_cmux_cli new-workspace --name "$TITLE" --cwd /tmp --focus false --window "$WIN_B" --id-format uuids 2>&1)
REF=$(fm_backend_cmux_created_workspace_ref "$RAW")
[ -n "$REF" ] || { echo "ABORT: new-workspace returned no ref ([$RAW])"; exit 2; }
sleep 1.5
echo "partial workspace created in window B: $REF"

# Make the partial workspace the LAST one in that window, the trap case.
SEED=$(fm_backend_cmux_cli workspace list --json --id-format both --window "$WIN_B" 2>/dev/null \
  | jq -r --arg r "$REF" '.workspaces[]? | select(.ref != $r) | .ref' | head -1)
[ -n "$SEED" ] && fm_backend_cmux_cli close-workspace --workspace "$SEED" >/dev/null 2>&1
sleep 1.5
echo "  window B now holds only the partial workspace:"; show_window "$WIN_B"

echo
echo "--- cleanup of a partial workspace that is LAST in its window ---"
set +e
out=$(fm_backend_cmux_close_created_workspace "$REF" "$TITLE" 2>&1); st=$?
set -e
echo "  status: $st (0 = removal confirmed)"
[ -n "$out" ] && echo "  message: $out"
sleep 1.5
echo "  window B afterwards:"; show_window "$WIN_B"
SURV=$(for w in $(fm_backend_cmux_cli list-windows --json --id-format uuids | jq -r '.[].id'); do
  fm_backend_cmux_cli workspace list --json --id-format both --window "$w" 2>/dev/null | jq -r --arg r "$REF" '.workspaces[]?|select(.ref==$r)|.ref'
done)
if [ "$st" -eq 0 ] && [ -z "$SURV" ]; then
  echo "  OK: the last-in-window partial workspace really went away, and the window was left with a fresh default workspace"
else
  echo "  FAIL: status=$st, still live=[${SURV:-<none>}]"
fi
