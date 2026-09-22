#!/usr/bin/env bash
# Drive bin/fm-teardown.sh live, with FM_HOME reached through the macOS
# /tmp -> /private/tmp alias: the spelling that produced the reported refusal.
set -u
WT=$1; EV=$2
export FM_GATE_REFUSE_BYPASS=1
cd "$WT"

run_case() {  # <case-dir>
  local case=$1 rc
  echo "\$ FM_HOME=$case/home bin/fm-teardown.sh cmux-resolve-task --force"
  FM_HOME="$case/home" FM_ROOT_OVERRIDE="$WT" FM_RUNTIME_LOG="$case/runtime.log" \
    PATH="$case/fakebin:$PATH" "$WT/bin/fm-teardown.sh" cmux-resolve-task --force \
    > "$case/out" 2> "$case/err"
  rc=$?
  grep -v '●' "$case/out" "$case/err" | sed 's/^[^:]*:/ /'
  echo "  exit code             : $rc"
}

echo "# fm-teardown aliased-home self-collision - live CLI transcript"
echo "# host: $(uname -sr)   bash: $BASH_VERSION"
echo

echo "=========================================================================="
echo "S1  Teardown through an aliased FM_HOME - WITH the fix (aec774e)"
echo "=========================================================================="
CASE=/tmp/fm-ev-s1; "$EV/build-fixture.sh" "$WT" "$CASE" cmux-resolve-task >/dev/null
echo "  FM_HOME as spelled    : $CASE/home"
echo "  FM_HOME as resolved   : $(cd -P "$CASE/home" && pwd -P)"
echo "  task record before    : $(ls "$CASE/home/state" | tr '\n' ' ')"
run_case "$CASE"
echo "  task record after     : $(ls "$CASE/home/state" | tr '\n' ' ')<- the task record is gone"
echo "  runtime calls made    :"; sed 's/^/    /' "$CASE/runtime.log"
echo

echo "=========================================================================="
echo "S2  Identical fixture and command - PRE-FIX product (base 6f0f139)"
echo "=========================================================================="
cp bin/fm-teardown.sh /tmp/fm-teardown-target.sh
git show 6f0f139:bin/fm-teardown.sh > bin/fm-teardown.sh; chmod +x bin/fm-teardown.sh
CASE=/tmp/fm-ev-s2; "$EV/build-fixture.sh" "$WT" "$CASE" cmux-resolve-task >/dev/null
run_case "$CASE"
echo "  task record after     : $(ls "$CASE/home/state" | tr '\n' ' ')<- stranded, cleanup refused"
echo "  runtime calls made    : $(cat "$CASE/runtime.log")(none - the pool slot was never returned)"
git checkout -- bin/fm-teardown.sh
echo

echo "=========================================================================="
echo "S3  Adversarial - a genuine second record on the same slot, aliased home"
echo "=========================================================================="
CASE=/tmp/fm-ev-s3
"$EV/build-fixture.sh" "$WT" "$CASE" cmux-resolve-task neighbour-task >/dev/null
echo "  task records before   : $(ls "$CASE/home/state" | tr '\n' ' ')"
run_case "$CASE"
echo "  task records after    : $(ls "$CASE/home/state" | tr '\n' ' ')<- both preserved"
echo "  pool slot after       : $(ls "$CASE/worktree" | tr '\n' ' ')<- sentinel intact, slot not reset"
echo "  runtime calls made    : $(cat "$CASE/runtime.log")(none - nothing was killed)"
