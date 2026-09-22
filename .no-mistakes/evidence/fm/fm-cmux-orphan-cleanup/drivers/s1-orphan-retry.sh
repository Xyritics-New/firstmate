#!/usr/bin/env bash
# S1: the user-visible intent. A cmux task create that fails AFTER cmux has
# already made the workspace must leave nothing behind, so the next attempt
# creates the task instead of being refused with "already exists".
#
# The failure is injected at the cmux boundary (the shim fails list-panes once);
# every other call - new-workspace, workspace list, list-windows,
# close-workspace - goes to the real running cmux app.
set -u
ROOT=$1
ADAPTER=${2:-cmux}
. "$ROOT/bin/fm-backend.sh"
if [ "$ADAPTER" = cmux ]; then
  fm_backend_source cmux
else
  # shellcheck source=/dev/null
  . "$ROOT/bin/backends/$ADAPTER.sh"
fi
. "$ROOT/tests/cmux-test-safety.sh"

LABEL=fm-test-orphan
TITLE=$(fm_backend_cmux_scoped_title "$LABEL")

live_refs_for_title() {
  local w
  for w in $(fm_backend_cmux_cli list-windows --json --id-format uuids 2>/dev/null | jq -r '.[]?|.id'); do
    fm_backend_cmux_cli workspace list --json --id-format both --window "$w" 2>/dev/null \
      | jq -r --arg t "$TITLE" '.workspaces[]? | select(.title == $t) | "\(.ref) \(.id)"'
  done
}

echo "### adapter under test: bin/backends/$ADAPTER.sh"
echo "### scoped workspace title: $TITLE"
echo "### pre-state for that title: [$(live_refs_for_title | tr '\n' ' ')]"

echo
echo "### ATTEMPT 1 - cmux creates the workspace, the post-create step then fails"
export FM_SETTLE=1
export FM_FAULT=list-panes-once FM_FAULT_FLAG=$TMPDIR/fm-fault-$$
rm -f "$FM_FAULT_FLAG"
set +e
out1=$(fm_backend_cmux_create_task "$LABEL" /tmp 2>&1); st1=$?
set -e
echo "exit status: $st1"
echo "message to the operator: $out1"
unset FM_FAULT FM_FAULT_FLAG

sleep 1
LEFT=$(live_refs_for_title)
echo
echo "### live cmux, every window, workspaces still carrying that title: [${LEFT:-<none>}]"

echo
echo "### ATTEMPT 2 - the retry an operator makes next"
set +e
out2=$(fm_backend_cmux_create_task "$LABEL" /tmp 2>&1); st2=$?
set -e
echo "exit status: $st2"
echo "result: $out2"
WS=$(printf '%s' "$out2" | awk '{print $1}')

if [ "$st2" -eq 0 ] && [ -n "$WS" ]; then
  echo "OUTCOME: the retry created the task (workspace $WS) - no orphan blocked it"
  sleep 0.5
  cmux_safe_close_workspace "$WS" "$LABEL" && echo "cleanup: closed the retry's workspace via the test safety guard"
else
  echo "OUTCOME: the retry was REFUSED - the failed create left an orphan behind"
fi

sleep 0.5
FINAL=$(live_refs_for_title)
echo "### final live state for that title: [${FINAL:-<none>}]"
