# Decision records

A decision record (DR) documents one settled, final decision about routnix's
design: what was decided and why, not the discussion that led to it.

Each file covers exactly **one** decision. If a decision relates to or builds
on another one, link to it by file name instead of restating it.

## Naming

`short-lowercase-decision-name.md` — the shortest name that still identifies
the decision unambiguously. Words separated by hyphens, no numbering prefix.

## Structure

Every decision record follows this structure:

```
# Context

One or two sentences stating the goal and what the decision is trying to
achieve and cover.

# Decision

What was decided, and why.

A short explanation of what it means in practice, with sample code
(shortened to the relevant parts, or pseudo-code) if useful.
```

## Relationship to `rfc/`

Open design questions without a final decision yet live in
[`../rfc`](../rfc) instead. Once an RFC reaches a final decision, write the
outcome as a new file here and delete the corresponding `rfc/` file.
