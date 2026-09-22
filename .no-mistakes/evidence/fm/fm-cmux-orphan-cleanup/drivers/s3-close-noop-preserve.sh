#!/usr/bin/env bash
# S3 (adversarial): cmux answers OK to close-workspace and removes nothing -
# the documented misleading-success shape. Cleanup must never report a removal
# it did not achieve, and must leave the workspace standing for the operator.
set -u
ROOT=$1
. "$ROOT/bin/fm-backend.sh"; fm_backend_source cmux
. "$ROOT/tests/cmux-test-safety.sh"
LABEL=fm-test-closenoop
TITLE=$(fm_backend_cmux_scoped_title "$LABEL")
export FM_SHIM_LOG=$2; : > "$FM_SHIM_LOG"
export FM_SETTLE=1 FM_FAULT=list-panes-once,close-workspace-noop
export FM_FAULT_FLAG=${TMPDIR:-/tmp}/fm-fault-$$; rm -f "$FM_FAULT_FLAG"

set +e
out=$(fm_backend_cmux_create_task "$LABEL" /tmp 2>&1); st=$?
set -e
unset FM_FAULT
echo "exit status: $st"
echo "message to the operator: $out"
case "$out" in
  *"removed the partial workspace"*) echo "FAIL: claimed a removal cmux did not perform" ;;
  *"in place; preserving it"*)       echo "OK: reported the workspace as still in place, not removed" ;;
  *)                                  echo "FAIL: unexpected message shape" ;;
esac
echo
echo "--- cmux calls made during cleanup ---"; cat "$FM_SHIM_LOG"; echo "---"
sleep 1
SURV=$(fm_backend_cmux_cli workspace list --json --id-format both 2>/dev/null | jq -r --arg t "$TITLE" '.workspaces[]? | select(.title==$t) | "\(.ref) \(.id)"')
echo "live cmux, workspaces carrying that title: [${SURV:-<none>}]"
[ -n "$SURV" ] && echo "OK: the workspace really is still there, matching what the operator was told"
[ -z "$SURV" ] || cmux_safe_close_workspace "$(printf '%s' "$SURV" | awk '{print $2}')" "$LABEL" && echo "cleanup: removed for real now that the injected no-op is off"
