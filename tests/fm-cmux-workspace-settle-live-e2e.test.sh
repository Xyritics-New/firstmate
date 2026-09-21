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
# over, and additionally measures the raw un-retried read so a build where the
# staleness disappears is reported rather than silently passing as proof.
#
# Touches and closes ONLY the fm-test- workspaces it creates itself, through
# tests/cmux-test-safety.sh's guarded close; it never enumerates-and-closes,
# and never quits or relaunches the captain's own cmux app.
set -u

# shellcheck source=tests/lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ROUNDS=${FM_CMUX_WORKSPACE_SETTLE_ROUNDS:-5}

fail() { printf 'not ok - %s\n' "$1" >&2; exit 1; }
pass() { printf 'ok - %s\n' "$1"; }

# The cmux CLI ships inside the app bundle and only lands on PATH when the
# operator ran cmux's optional "install CLI" action, so make the bundle copy
# visible before the gate decides whether this host can run the guard.
BUNDLE_BIN=${FM_BACKEND_CMUX_BUNDLE_BIN:-/Applications/cmux.app/Contents/Resources/bin/cmux}
if ! command -v cmux >/dev/null 2>&1 && [ -x "$BUNDLE_BIN" ]; then
  PATH="$(dirname "$BUNDLE_BIN"):$PATH"
  export PATH
fi

fm_live_gate default-on FM_CMUX_WORKSPACE_SETTLE_LIVE cmux jq

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

CMUX_VERSION=$(cmux version 2>/dev/null | head -1)
[ -n "$CMUX_VERSION" ] \
  || gate_gap "cmux is installed but 'cmux version' produced nothing, so this host has no identifiable cmux to report a pass against"

# shellcheck source=bin/fm-backend.sh
. "$ROOT/bin/fm-backend.sh"
fm_backend_source cmux || gate_gap "could not source the cmux adapter"

fm_backend_cmux_version_check >/dev/null 2>&1 \
  || gate_gap "installed cmux is older than the verified minimum the adapter requires"

PING_STATE=$(fm_backend_cmux_ping_state)
[ "$PING_STATE" = ok ] \
  || gate_gap "cmux socket is not reachable/authenticated (state=$PING_STATE) - see docs/cmux-backend.md 'Setup'"

# shellcheck source=tests/cmux-test-safety.sh
. "$ROOT/tests/cmux-test-safety.sh"

# Every workspace this guard asks cmux to create is registered by LABEL BEFORE
# the create call, so a failure anywhere between the create and the id resolve
# still leaves the EXIT trap something to close. Teardown resolves each label's
# own scoped title back to an id and hands it to tests/cmux-test-safety.sh's
# guarded close, which re-checks it; a label whose workspace is already gone
# resolves to nothing and is skipped.
OPEN_LABELS=()

track() {  # <label>
  OPEN_LABELS+=("$1")
}

close_tracked() {  # <label>
  local wsid
  wsid=$(fm_backend_cmux_workspace_id_for_label "$(fm_backend_cmux_scoped_title "$1")")
  [ -z "$wsid" ] || cmux_safe_close_workspace "$wsid" "$1"
}

cleanup_all() {
  local i
  for i in "${!OPEN_LABELS[@]}"; do
    close_tracked "${OPEN_LABELS[$i]}"
  done
}
trap cleanup_all EXIT

STALE_SEEN=0
ROUND=1
while [ "$ROUND" -le "$ROUNDS" ]; do
  # --- raw sequence: is the un-retried post-create read actually stale here? --
  RAW_LABEL="fm-test-settle-raw-$$-$ROUND"
  RAW_TITLE=$(fm_backend_cmux_scoped_title "$RAW_LABEL")
  fm_backend_cmux_workspace_id_for_label "$RAW_TITLE" >/dev/null
  track "$RAW_LABEL"
  fm_backend_cmux_cli new-workspace --name "$RAW_TITLE" --cwd /tmp --focus false --id-format uuids >/dev/null 2>&1 \
    || fail "$CMUX_VERSION refused to create the probe workspace '$RAW_TITLE'"
  RAW_IMMEDIATE=$(fm_backend_cmux_workspace_id_for_label "$RAW_TITLE")
  [ -n "$RAW_IMMEDIATE" ] || STALE_SEEN=$((STALE_SEEN + 1))
  # Resolved with the guard's own loop, not the adapter's settle helper, so a
  # regression shows up as create_task failing below rather than as this probe
  # failing to clean up after itself.
  RAW_ID=$RAW_IMMEDIATE
  RAW_TRY=1
  while [ -z "$RAW_ID" ] && [ "$RAW_TRY" -le 40 ]; do
    sleep 0.25
    RAW_ID=$(fm_backend_cmux_workspace_id_for_label "$RAW_TITLE")
    RAW_TRY=$((RAW_TRY + 1))
  done
  [ -n "$RAW_ID" ] \
    || fail "$CMUX_VERSION never published workspace '$RAW_TITLE' within 10s, so the probe cannot be trusted"
  cmux_safe_close_workspace "$RAW_ID" "$RAW_LABEL"

  # --- the adapter's own sequence, which must survive that staleness ---------
  LABEL="fm-test-settle-$$-$ROUND"
  track "$LABEL"
  IDS=$(fm_backend_cmux_create_task "$LABEL" /tmp) \
    || fail "$CMUX_VERSION: fm_backend_cmux_create_task failed on round $ROUND of $ROUNDS - the post-creation settle did not absorb cmux's stale workspace snapshot"
  read -r WSID SFID <<CREATED
$IDS
CREATED
  [ -n "${WSID:-}" ] && [ -n "${SFID:-}" ] \
    || fail "$CMUX_VERSION: create_task returned no workspace/surface pair on round $ROUND (got '$IDS')"
  fm_backend_cmux_surface_exists "$WSID" "$SFID" \
    || fail "$CMUX_VERSION: create_task's resolved surface $SFID is not live in workspace $WSID on round $ROUND"
  cmux_safe_close_workspace "$WSID" "$LABEL"

  ROUND=$((ROUND + 1))
done

pass "real cmux ($CMUX_VERSION): create_task resolved its new workspace and surface on all $ROUNDS rounds"
if [ "$STALE_SEEN" -gt 0 ]; then
  pass "real cmux ($CMUX_VERSION): the raw un-retried post-create read was stale in $STALE_SEEN of $ROUNDS rounds, so the window the settle covers is live on this build"
else
  printf 'ok - real cmux (%s): no stale post-create read observed in %s rounds; the settle is untriggered on this build and only the success path was proven\n' \
    "$CMUX_VERSION" "$ROUNDS"
fi
