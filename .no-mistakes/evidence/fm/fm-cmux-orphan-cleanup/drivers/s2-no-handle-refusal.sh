#!/usr/bin/env bash
# S2 (adversarial): cmux really creates the workspace but hands back no handle
# for it. Nothing can be attributed to this call, so the adapter must refuse
# plainly, issue no close at all, and leave the workspace standing.
set -u
ROOT=$1
. "$ROOT/bin/fm-backend.sh"; fm_backend_source cmux
. "$ROOT/tests/cmux-test-safety.sh"
LABEL=fm-test-nohandle
TITLE=$(fm_backend_cmux_scoped_title "$LABEL")
export FM_SHIM_LOG=$2; : > "$FM_SHIM_LOG"
export FM_SETTLE=1 FM_FAULT=new-workspace-no-ref

set +e
out=$(fm_backend_cmux_create_task "$LABEL" /tmp 2>&1); st=$?
set -e
unset FM_FAULT
echo "exit status: $st"
echo "message to the operator: $out"
echo
echo "--- every cmux call this create made ---"
cat "$FM_SHIM_LOG"
echo "---"
if grep -q '^close-workspace' "$FM_SHIM_LOG"; then
  echo "FAIL: the adapter closed something it could not prove it created"
else
  echo "OK: no close-workspace was issued at all"
fi
sleep 1
SURV=$(fm_backend_cmux_cli workspace list --json --id-format both 2>/dev/null | jq -r --arg t "$TITLE" '.workspaces[]? | select(.title==$t) | "\(.ref) \(.id)"')
echo "live cmux, workspaces carrying that title: [${SURV:-<none>}]"
if [ -n "$SURV" ]; then
  echo "OK: the workspace cmux actually made is preserved, not guessed at and deleted"
  cmux_safe_close_workspace "$(printf '%s' "$SURV" | awk '{print $2}')" "$LABEL" && echo "cleanup: removed by hand through the test safety guard"
else
  echo "NOTE: nothing survived - check whether the real create happened"
fi
