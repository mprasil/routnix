# Context

`routeros.config` item values are currently loosely typed (`bool | int |
str`). RouterOS's own per-field syntax (CIDR, MAC, port lists/ranges,
negation, etc.) is much more specific than that.

# Options considered

## Keep the low-level DSL loosely typed

`bool | int | str`, maybe plus `listOf str` with comma-joining for
convenience. Modeling RouterOS's per-field syntax generically at this
freeform layer seems like poor ROI: it would mean encoding CIDR/MAC/port-
list/negation syntax generically, independent of which path/field it's
attached to.

## Model RouterOS's per-field syntax generically at the DSL layer

Give the low-level DSL itself stricter, RouterOS-aware types (CIDR, MAC,
port lists/ranges, negation, etc.), applied uniformly regardless of which
field they're attached to.

## Put stricter types only in high-level typed modules

Once typed modules exist (see
[`high-level-modules.md`](./high-level-modules.md)), model a field's exact
semantics there, where the specific field's meaning is actually known,
rather than generically at the freeform low-level layer.

Leaning towards the first option combined with the third; not revisited
since first raised, open to reconsidering once there are a couple of
high-level modules to see what they actually need.
