# RFCs

An RFC documents an open design question that hasn't been settled yet: the
options under consideration, without a final decision. Once a decision is
made, write it up as a new file under [`../dr`](../dr) and delete this file.

Each file covers exactly one open question.

## Naming

`short-lowercase-decision-name.md` — the shortest name that still identifies
the question unambiguously. Words separated by hyphens, no numbering prefix.

## Structure

Every RFC follows this structure:

```
# Context

One or two sentences stating the goal and what the decision is trying to
achieve and cover.

# Options considered

## Some option description

A short description of this option, in the same style as a decision
record's "Decision" section: why it's an option, and what it means in
practice (sample code, shortened to the relevant parts, or pseudo-code, if
useful).

## Some other option description

... one `##` sub-heading per option.
```

There is no `# Decision` section — that's what distinguishes an RFC from a
decision record.
