#!/usr/bin/env bash
# S4 (adversarial, the multi-window boundary): the partial workspace sits in
# window A while the operator has focused window B. A plain `workspace list`
# answers for the CURRENT window only, so an absence check read from it would
# call the workspace removed while it is still sitting in A.
set -u
ROOT=$1
. "$ROOT/bin/fm-backend.sh"; fm_backend_source cmux
. "$ROOT/tests/cmux-test-safety.sh"
LABEL=fm-test-otherwin
TITLE=$(fm_backend_cmux_scoped_title "$LABEL")
WIN_B=""
UUID=""
cleanup() {
  [ -z "$WIN_B" ] || fm_backend_cmux_cli close-window --window "$WIN_B" >/dev/null 2>&1
  [ -z "$UUID" ] || cmux_safe_close_workspace "$UUID" "$LABEL" >/dev/null 2>&1
}
trap cleanup EXIT

WIN_A=$(fm_backend_cmux_cli list-windows --json --id-format uuids | jq -r '.[0].id')
echo "window A (where the partial workspace will live): $WIN_A"

RAW=$(fm_backend_cmux_cli new-workspace --name "$TITLE" --cwd /tmp --focus false --id-format uuids 2>&1)
REF=$(fm_backend_cmux_created_workspace_ref "$RAW")
[ -n "$REF" ] || { echo "ABORT: new-workspace returned no ref ([$RAW]); refusing to act on an unproven target"; exit 2; }
sleep 1.5
UUID=$(fm_backend_cmux_workspace_id_for_ref "$REF")
[ -n "$UUID" ] || { echo "ABORT: ref $REF did not resolve"; exit 2; }
echo "partial workspace: ref=$REF uuid=$UUID (created in window A)"

WIN_B=$(fm_backend_cmux_cli new-window 2>&1 | awk '{print $2}')
[ -n "$WIN_B" ] || { echo "ABORT: could not open a second window"; exit 2; }
sleep 1.5
echo "window B (opened second, now the frontmost/current window): $WIN_B"

echo
echo "--- what an unscoped 'workspace list' (CURRENT window only) sees ---"
fm_backend_cmux_cli workspace list --json --id-format both 2>/dev/null | jq -r '.workspaces[]? | "  \(.ref)\t\(.title)"'
if fm_backend_cmux_cli workspace list --json --id-format both 2>/dev/null | jq -e --arg r "$REF" 'any(.workspaces[]?; .ref == $r)' >/dev/null; then
  echo "  => the ref IS visible in the current-window list"
else
  echo "  => the ref is NOT visible there: a current-window-only absence check would call it removed"
fi

echo
echo "--- the adapter's own every-window walk, which must still find it ---"
echo "  window_of_workspace($REF) = [$(fm_backend_cmux_window_of_workspace "$REF")]"

echo
echo "--- cleanup while cmux answers OK to close-workspace and removes nothing ---"
export FM_FAULT=close-workspace-noop
set +e
out=$(fm_backend_cmux_close_created_workspace "$REF" "$TITLE" 2>&1); st=$?
set -e
unset FM_FAULT
echo "  status: $st (non-zero = did not claim a removal)"
echo "  message: $out"
case "$out" in
  *"in place; preserving it"*) echo "  OK: refused to report removal for a workspace stranded in a non-current window" ;;
  *) echo "  FAIL: did not report the workspace as preserved" ;;
esac

echo
echo "--- the honest positive: a real cross-window close from window B ---"
set +e
out2=$(fm_backend_cmux_close_created_workspace "$REF" "$TITLE" 2>&1); st2=$?
set -e
echo "  status: $st2 (0 = removal confirmed)"
[ -n "$out2" ] && echo "  message: $out2"
sleep 1.5
SURV=$(for w in $(fm_backend_cmux_cli list-windows --json --id-format uuids | jq -r '.[].id'); do
  fm_backend_cmux_cli workspace list --json --id-format both --window "$w" 2>/dev/null | jq -r --arg t "$TITLE" '.workspaces[]?|select(.title==$t)|.ref'
done)
echo "  live cmux, every window, workspaces carrying that title: [${SURV:-<none>}]"
if [ "$st2" -eq 0 ] && [ -z "$SURV" ]; then
  echo "  OK: the cross-window close really removed it and said so"
  UUID=""
else
  echo "  FAIL: reported status and live state disagree"
fi
