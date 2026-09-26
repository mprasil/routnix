# Context

`routeros.config` needs one attrset key per RouterOS path. RouterOS v6 and
v7 use different path syntaxes, and rendered `.rsc` scripts need to work on
both.

# Decision

`routeros.config` is keyed by the v6 form: leading slash, then
space-separated. v7's `/`-separated form is a superset only v7 understands,
while the space-separated form is what keeps rendered `.rsc` scripts
working on both v6 and v7.
