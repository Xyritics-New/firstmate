#!/usr/bin/env bash
# Build a live fm-teardown fixture whose FM_HOME is reached through the macOS
# /tmp -> /private/tmp alias (the spelling that surfaced the bug), then run the
# real bin/fm-teardown.sh CLI against it exactly as an operator would.
set -eu
umask 022
REPO=$1        # firstmate checkout to run bin/fm-teardown.sh from
CASE=$2        # fixture directory under /tmp (aliased spelling)
ID=${3:-cmux-resolve-task}
EXTRA_RECORD=${4:-}

rm -rf "$CASE"
mkdir -p "$CASE/home/state" "$CASE/home/data" "$CASE/home/config" \
  "$CASE/fakebin" "$CASE/project"
git init -q "$CASE/project"
git -C "$CASE/project" -c user.name=test -c user.email=test@example.invalid \
  commit --allow-empty -qm pool-fixture
: > "$CASE/runtime.log"

for tool in tmux treehouse; do
  cat > "$CASE/fakebin/$tool" <<SH
#!/usr/bin/env bash
printf '$tool' >> "\${FM_RUNTIME_LOG:?}"
printf ' <%s>' "\$@" >> "\${FM_RUNTIME_LOG:?}"
printf '\n' >> "\${FM_RUNTIME_LOG:?}"
exit 0
SH
  chmod +x "$CASE/fakebin/$tool"
done

# Real Treehouse pool slot, so the exclusivity guard actually runs.
mkdir -p "$CASE/pool/1"
git -C "$CASE/project" worktree add -q --detach "$CASE/pool/1/project"
ln -s "pool/1/project" "$CASE/worktree"
printf '{"worktrees":[{"name":"1","path":"%s"}]}\n' "$CASE/pool/1/project" \
  > "$CASE/pool/treehouse-state.json"
: > "$CASE/worktree/sentinel"

write_meta() {
  local id=$1
  printf 'window=firstmate:fm-%s\nendpoint_task_id=%s\nworktree=%s\nproject=%s\nkind=scout\n' \
    "$id" "$id" "$CASE/worktree" "$CASE/project" > "$CASE/home/state/$id.meta"
}
write_meta "$ID"
[ -z "$EXTRA_RECORD" ] || write_meta "$EXTRA_RECORD"
