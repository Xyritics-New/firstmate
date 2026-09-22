# Live cmux orphan-cleanup evidence

Everything here was driven against the real, running cmux 0.64.x app on this
machine, through the adapter under test (`bin/backends/cmux.sh`). No cmux call
was faked. A passthrough shim (`shimbin/cmux`) forwards every call to the real
`/opt/homebrew/bin/cmux` and only:

* pauses after `new-workspace` (`FM_SETTLE=1`) so the app has published the
  workspace before the adapter lists it - this machine currently loses that
  publication race on *every* create, at the base commit too, which would
  otherwise make every create fail for a reason unrelated to this change; and
* breaks one specific cmux call (`FM_FAULT=...`) to stage the post-create
  failures the change is about.

Only `fm-test-`-prefixed workspaces were created, under this worktree's own
home tag (`fm-firstmate-584feda8-*`), which is a different scope from the
operator's live fleet titles (`fm-firstmate-e2cba94a-*`). Every close was
either by a ref the run's own `new-workspace` returned or through
`tests/cmux-test-safety.sh`'s title-verified guard. Throwaway windows were
opened and closed within the same run.

| file | scenario |
| --- | --- |
| `s0-ref-contract.log` | the live cmux handle contract the change rests on |
| `s0b-stale-list-timing.log` | how long the post-create list stays stale |
| `s0c-plain-create-trials.log` | the publication race, unpaced, on this machine |
| `s1-baseline-6f0f139-orphan-blocks-retry.log` | the reported bug, live, at the base commit |
| `s1-fixed-118256b-retry-succeeds.log` | the same drive on the fix |
| `s2-no-handle-refusal.log` + `s2-shim-calls.log` | no handle -> refuse and preserve |
| `s3-close-noop-preserve.log` + `s3-shim-calls.log` | close says OK, removes nothing |
| `s4-other-window.log` | partial workspace stranded in a non-current window |
| `s5-real-cmux-smoke.log` | the repo's own real-cmux smoke suite |
| `s6-fake-cli-suite.log` | the adapter's fake-CLI suite |
| `s7-last-in-window.log` | last-workspace-in-a-window cleanup, live |
| `s8-sibling-fails.log` | the throwaway sibling cmux refuses to create |
| `s9-unconfirmable.log` | removal that cannot be confirmed |
