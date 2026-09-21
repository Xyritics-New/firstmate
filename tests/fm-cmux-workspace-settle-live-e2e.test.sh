#!/usr/bin/env bash
# tests/fm-cmux-workspace-settle-live-e2e.test.sh - real-cmux guard for the
# post-creation settle in bin/backends/cmux.sh's fm_backend_cmux_create_task.
#
# The verdict this pins comes from what cmux itself emits: `workspace list` is
# not read-your-writes against `new-workspace`, so the read that resolves a
# freshly created workspace's id can be served a snapshot that predates it.
# No fake CLI can prove that, because a fake only replays the assumption
# already written into it - hence this live guard alongside the portable
# regression in tests/fm-backend-cmux.test.sh.
#
# It drives the adapter's own create_task through the exact
# duplicate-check-then-create sequence that exposed the fault, several rounds
# over.
#
# Touches and closes ONLY the fm-test- workspaces it creates itself, through
# tests/cmux-test-safety.sh's guarded close; it never enumerates-and-closes,
# and never quits or relaunches the captain's own cmux app.
set -u

# shellcheck source=tests/lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

# A cmux that cannot be identified, is below the adapter's verified minimum, or
# whose control socket is unreachable is the same class of host-capability gap
# fm_live_gate already decides for an absent tool, so it takes the same verdict:
# a named skip by default, and a loud failure when this guard was explicitly
# requested via its own variable or FM_LIVE=1. cmux ships defaulting to
# socketControlMode=cmuxOnly, which rejects every external CLI process, so an
# installed-but-unreachable cmux is an ordinary unconfigured host, not a
# regression (docs/cmux-backend.md "Setup").
gate_gap() {  # <message>
  local detail=$1
  [ -z "${CMUX_VERSION:-}" ] || detail="$CMUX_VERSION: $detail"
  if [ "${FM_CMUX_WORKSPACE_SETTLE_LIVE:-${FM_LIVE:-0}}" = 1 ]; then
    fail "$detail"
  fi
  printf 'skip: live: %s\n' "$detail"
  exit 0
}

# shellcheck source=bin/fm-backend.sh
. "$ROOT/bin/fm-backend.sh"
fm_backend_source cmux || gate_gap "could not source the cmux adapter"

# The cmux CLI ships inside the app bundle and only lands on PATH when the
# operator ran cmux's optional "install CLI" action, so make the bundle copy
# visible before the gate decides whether this host can run the guard. The
# bundle path is the adapter's to own, so ask fm_backend_cmux_bin for it
# rather than re-reading its variable.
if ! command -v cmux >/dev/null 2>&1 && CMUX_BUNDLE_BIN=$(fm_backend_cmux_bin); then
  PATH="$(dirname "$CMUX_BUNDLE_BIN"):$PATH"
  export PATH
fi

fm_live_gate default-on FM_CMUX_WORKSPACE_SETTLE_LIVE cmux jq

CMUX_VERSION=$(cmux version 2>/dev/null | head -1)
[ -n "$CMUX_VERSION" ] \
  || gate_gap "cmux is installed but 'cmux version' produced nothing, so this host has no identifiable cmux to report a pass against"

fm_backend_cmux_version_check >/dev/null 2>&1 \
  || gate_gap "installed cmux is older than the verified minimum the adapter requires"

PING_STATE=$(fm_backend_cmux_ping_state)
[ "$PING_STATE" = ok ] \
  || gate_gap "cmux socket is not reachable/authenticated (state=$PING_STATE) - see docs/cmux-backend.md 'Setup'"

# shellcheck source=tests/cmux-test-safety.sh
. "$ROOT/tests/cmux-test-safety.sh"

# TRACKED_LABELS carries every label this guard has created and not yet seen
# gone: appended BEFORE the create call, so a failure anywhere between the
# create and the id resolve still leaves the EXIT trap something to close, and
# dropped only once the scoped title no longer resolves to a live workspace -
# cmux's close-workspace reports OK even where it silently declines to act, so
# the listing, not the close's exit status, is what retires a record.
TRACKED_LABELS=""

track_label() {  # <label>
  TRACKED_LABELS="$TRACKED_LABELS$1
"
}

# Teardown resolves through the adapter's settled read: every label still held
# here is one cmux is expected to be showing, either because a failed
# create_task abandoned a workspace cmux has not published yet or because a
# close did not take.
untrack_closed_label() {  # <label>
  local label=$1 kept="" entry
  [ -z "$(fm_backend_cmux_workspace_id_for_label "$(fm_backend_cmux_scoped_title "$label")")" ] || return 0
  while IFS= read -r entry; do
    [ -n "$entry" ] || continue
    [ "$entry" = "$label" ] || kept="$kept$entry
"
  done <<TRACKED
$TRACKED_LABELS
TRACKED
  TRACKED_LABELS=$kept
}

cleanup_all() {
  local entry wsid
  while IFS= read -r entry; do
    [ -n "$entry" ] || continue
    wsid=$(fm_backend_cmux_workspace_id_settled "$(fm_backend_cmux_scoped_title "$entry")")
    [ -z "$wsid" ] || cmux_safe_close_workspace "$wsid" "$entry"
  done <<TRACKED
$TRACKED_LABELS
TRACKED
  fm_test_cleanup
}
trap cleanup_all EXIT

ROUND=1
while [ "$ROUND" -le 5 ]; do
  LABEL="fm-test-settle-$$-$ROUND"
  track_label "$LABEL"
  IDS=$(fm_backend_cmux_create_task "$LABEL" /tmp) \
    || fail "$CMUX_VERSION: fm_backend_cmux_create_task failed on round $ROUND of 5 - the post-creation settle did not absorb cmux's stale workspace snapshot"
  read -r WSID SFID <<CREATED
$IDS
CREATED
  [ -n "${WSID:-}" ] && [ -n "${SFID:-}" ] \
    || fail "$CMUX_VERSION: create_task returned no workspace/surface pair on round $ROUND (got '$IDS')"
  fm_backend_cmux_surface_exists "$WSID" "$SFID" \
    || fail "$CMUX_VERSION: create_task's resolved surface $SFID is not live in workspace $WSID on round $ROUND"
  cmux_safe_close_workspace "$WSID" "$LABEL"
  untrack_closed_label "$LABEL"

  ROUND=$((ROUND + 1))
done

pass "real cmux ($CMUX_VERSION): create_task resolved its new workspace and surface on all 5 rounds"
