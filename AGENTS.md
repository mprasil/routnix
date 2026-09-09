# AGENTS.md

Guidance for AI coding agents working in this repo.

## What this is

`routnix` ("router" + "nix"): declarative router configuration via the Nix
module system, rendered to backend-specific scripts. **RouterOS (MikroTik)
only, for now and for the foreseeable future** — the name and the
`routeros` namespace are chosen so a future device-agnostic layer wouldn't
require a rename, not because multi-backend support is planned or in
scope. Very early / exploratory — most of the design is still open.

**Read `DESIGN.md` first.** Its "Settled" section is the actual current
state of the code; treat it as accurate. Its "Open design space" section is
discussion notes, not a spec — do not treat anything there as decided, and
do not silently pick one of the discussed options while implementing.
When in doubt about anything not covered by "Settled", ask rather than
assume.

## Layout

```
modules/routeros.nix    -- evalModules options (the low-level DSL, RouterOS-specific)
lib/toposort.nix         -- before/after -> ordered list (wraps lib.toposort)
lib/render_rsc.nix       -- ordered routeros.config -> .rsc text
lib/render_rsc/          -- per-kind rendering helpers used by render_rsc.nix
lib/default.nix          -- evalConfig { modules } entry point
examples/                -- example configs, incl. one that intentionally cycles
checks/                  -- RouterOS CHR integration check (requires KVM)
flake.nix                -- packages.<system>.example, .cycle-example,
                            checks.x86_64-linux.routeros
```

## Comments and option descriptions

Code comments and `mkOption` `description`s document current behavior —
what the code does or what an option controls — not the design discussion
or rationale behind it. Rationale, alternatives considered, and decision
history belong in `DESIGN.md`, not in `.nix` files.

- Don't narrate the design process (e.g. "settled", "decided", "direction
  discussed", "deliberately has no default because...") — just state what
  is true of the code as it stands.
- Don't editorialize or justify why an option is good/useful — describe
  its purpose and effect, not why it's a good idea.
- Don't document planned-but-unimplemented behavior or current limitations
  as if they were part of the design (e.g. "reapplying currently
  duplicates entries" on an option about ordering) — that's a `DESIGN.md`
  "Open design space" concern, not something a user of the option needs to
  know to use it correctly today.
- In `mkOption` `description`s specifically, describe things from the
  config author's point of view (what happens to their router / their
  declared entries), not the internal pipeline (e.g. `"set"`/`"add"` are
  fine — that's RouterOS's own vocabulary and what actually happens on the
  router; `"rendered"`, `"the .rsc text-generation step"`, or naming a
  specific function are internal, routnix-pipeline vocabulary and don't
  belong here, and are also liable to go stale if the implementation
  changes).
- Prefer no comment over one that just restates what the code obviously
  does.
- Keep it short: a sentence or a few bullet points, not a paragraph.

## Working in this repo

- Build and inspect output: `nix build .#example && cat result`.
- `nix build .#cycle-example` is expected to fail with a `routnix:
  dependency cycle detected` error — that's the cycle-detection path being
  exercised on purpose, not a bug.
- Use the shell tool's working-directory option to run commands in this
  repo; don't `cd` into it or pass `-C`.
- `nix build .#checks.x86_64-linux.routeros -L` boots a RouterOS CHR VM
  under QEMU, imports the `.rsc` rendered from `examples/basic.nix`, and
  checks the result over SSH. Requires KVM on the build host and network
  access to fetch the CHR image.
- That check only asserts that the expected entries exist, not their order,
  idempotence, or pruning — so "does it build and does the rendered `.rsc`
  look right" is still the main bar.
