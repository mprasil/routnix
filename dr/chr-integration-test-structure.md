# Context

The integration check needs to verify many independent behaviors (kinds,
pruning, `ignore`, ordering) against a real RouterOS CHR VM without every
failure looking the same, and without RouterOS's own success/failure
reporting being trusted blindly.

# Options considered

- One large config applied once, with a single broad assertion covering
  everything.
- One focused `checks/configs/*.nix` file per behavior, one subtest per
  file, each cleaning up after itself.
- The same per-file structure, but letting a few related subtests
  intentionally build on state left behind by the previous one.
- Trust `/import`'s exit code alone to determine success.
- Also inspect `/import`'s textual output for error-looking text.

# Decision

Each `checks/configs/*.nix` file isolates one behavior (e.g.
`ordered_basic.nix`, `unordered_prune.nix`, `effect_basic.nix`), and
`checks/routeros_test.py` runs one subtest per file — copying the rendered
`.rsc` to the VM over scp, running `/import`, and inspecting the result
over SSH — so a failure names the specific feature that broke rather than
"the result isn't as expected". Most subtests clean up whatever path they
touched afterward (`remove [find ...]`).

The `"ordered"`-kind and `users_*` groups are the exception, deliberately
building on the state the previous subtest left behind (add-in-order,
idempotent reapply, drift restoration via `move`, a field edit, then
`ignore`-guarded pruning for `"ordered"`; account/SSH-key add, prune, and
the `sshPubKeys = null` vs. `[ ]` distinction for `users_*`), since both
kinds' mandatory prune makes each apply a clean slate anyway. Every
`users_*` config declares `admin` with `create = false`, the account
`routeros_test.py` itself connects over SSH as.

All subtests run regardless of earlier failures. `/import`'s own textual
output is checked for error-looking text, not just its exit code, which
RouterOS can report as success even when the script errored.
