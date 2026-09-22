#!/usr/bin/env python3
"""Integration test: apply routnix-generated .rsc snippets to a RouterOS CHR VM
and verify the resulting router state, one focused subtest per feature.

Each subtest below corresponds to a config in checks/configs/ (built and handed
to us as "<name>.rsc" in --rsc-dir by checks/routeros.nix) plus, where needed,
some manual setup/cleanup over SSH. Subtests run in sequence against a single
booted VM. Ordering matters for a few of them - and most try to clean up
whatever they touched afterward, though this is somewhat optimistic best effort
only. We try to run all subtests even if an earlier one fails.

Exit codes: 0 = pass, non-zero = at least one subtest failed.

"""

from __future__ import annotations

import argparse
import shutil
import sys
import tempfile
import traceback
from pathlib import Path
from typing import Callable

from routeros_machine import RouterOsMachine
from test_driver.logger import TerminalLogger


def parse_args() -> argparse.Namespace:
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--image",    required=True, help="Path to the CHR .img file")
    p.add_argument("--rsc-dir",  required=True,
                   help="Directory of rendered '<config-name>.rsc' files "
                        "(one per checks/configs/*.nix)")
    p.add_argument("--qemu",     required=True, help="Path to qemu-system-x86_64")
    p.add_argument("--ssh",      required=True, help="Path to ssh binary")
    p.add_argument("--scp",      required=True, help="Path to scp binary")
    p.add_argument("--ssh-port", type=int, default=2222,
                   help="Host TCP port forwarded to RouterOS SSH")
    p.add_argument("--out-dir",  required=True,
                   help="Directory for test artefacts")
    return p.parse_args()


# --------------------------------------------------------------------------
# Assertion helpers
# --------------------------------------------------------------------------

def assert_contains(output: str, *needles: str, context: str = "") -> None:
    """Assert every needle appears in *output*; raise on the first miss."""
    for needle in needles:
        if needle not in output:
            raise AssertionError(
                f"expected {needle!r} in output"
                + (f" ({context})" if context else "")
                + f"\nActual output:\n{output}"
            )


def assert_not_contains(output: str, *needles: str, context: str = "") -> None:
    """Assert none of the needles appear in *output*."""
    for needle in needles:
        if needle in output:
            raise AssertionError(
                f"expected {needle!r} NOT in output"
                + (f" ({context})" if context else "")
                + f"\nActual output:\n{output}"
            )


def assert_order(output: str, *needles: str, context: str = "") -> None:
    """Assert every needle appears in *output*, in the given order."""
    positions = []
    for needle in needles:
        idx = output.find(needle)
        if idx < 0:
            raise AssertionError(
                f"expected {needle!r} in output"
                + (f" ({context})" if context else "")
                + f"\nActual output:\n{output}"
            )
        positions.append(idx)
    if positions != sorted(positions):
        raise AssertionError(
            f"expected {needles!r} in that order"
            + (f" ({context})" if context else "")
            + f", but found them at positions {positions}\nActual output:\n{output}"
        )


def assert_eq(actual, expected, *, context: str = "") -> None:
    if actual != expected:
        raise AssertionError(
            f"expected {expected!r}, got {actual!r}"
            + (f" ({context})" if context else "")
        )


# RouterOS's own `:error` calls (e.g. routnix's own ambiguous-`find`
# guards) and outright command failures don't reliably turn into a
# non-zero `/import` exit code, so `/import`'s own textual output has to
# be inspected too. This is a best-effort substring check, not a full
# parse of RouterOS's console grammar.
IMPORT_ERROR_MARKERS = ("error", "failure", "bad command", "syntax error")


def assert_import_ok(output: str, *, context: str = "") -> None:
    lowered = output.lower()
    for marker in IMPORT_ERROR_MARKERS:
        if marker in lowered:
            raise AssertionError(
                f"/import output looks like it failed (contains {marker!r})"
                + (f" ({context})" if context else "")
                + f"\nActual output:\n{output}"
            )


def count_only(ros: RouterOsMachine, path: str, where: str = "") -> int:
    """Run `<path> print count-only [where ...]` and parse the result."""
    cmd = f"{path} print count-only"
    if where:
        cmd += f" where {where}"
    out = ros.ssh_cmd(cmd).strip()
    try:
        return int(out)
    except ValueError as exc:
        raise AssertionError(f"expected an integer from {cmd!r}, got {out!r}") from exc


def import_config(ros: RouterOsMachine, rsc_dir: Path, config_name: str) -> str:
    """Upload and `/import` checks/configs/<config_name>.nix's rendered .rsc."""
    local = rsc_dir / f"{config_name}.rsc"
    remote = f"routnix-{config_name}.rsc"
    ros.scp_to_ros(local, remote)
    out = ros.ssh_cmd(f"/import {remote}", timeout=60)
    assert_import_ok(out, context=f"importing {config_name}.rsc")
    return out


# ----------------------------------------------------------------------------
# Subtests
#
# Each takes the running machine and the directory of rendered .rsc files, and
# raises AssertionError (or lets one propagate) on failure.
# ----------------------------------------------------------------------------

FILTER = "/ip firewall filter"
ADDRESS_LIST = "/ip firewall address-list"
USER = "/user"
USER_SSH_KEYS = "/user ssh-keys"
ETHERNET = "/interface ethernet"


def test_ordered_add(ros: RouterOsMachine, rsc_dir: Path) -> None:
    """kind = "ordered": missing items are added, already placed in
    declared order."""
    import_config(ros, rsc_dir, "ordered_basic")
    out = ros.ssh_cmd(f"{FILTER} print")
    assert_order(
        out,
        "routnix-test-ordered-icmp",
        "routnix-test-ordered-ssh",
        "routnix-test-ordered-web",
        "routnix-test-ordered-drop",
        context=f"{FILTER} print",
    )
    assert_contains(out, "dst-port=8080", context=f"{FILTER} print")
    # kind = "ordered" always prunes: only our 4 declared items should
    # remain, regardless of whatever else was in the table before.
    assert_eq(count_only(ros, FILTER), 4, context=f"{FILTER} count after ordered_basic")


def test_ordered_idempotent(ros: RouterOsMachine, rsc_dir: Path) -> None:
    """Reapplying the same config must not duplicate entries."""
    import_config(ros, rsc_dir, "ordered_basic")
    assert_eq(count_only(ros, FILTER), 4, context=f"{FILTER} count after reapplying ordered_basic")


def test_ordered_reorder(ros: RouterOsMachine, rsc_dir: Path) -> None:
    """An entry moved out of place since the last apply (by something
    other than routnix) is moved back into its declared position."""
    ros.ssh_cmd(
        f'{FILTER} move [find where comment="routnix-test-ordered-web"] '
        f'destination=[find where comment="routnix-test-ordered-icmp"]'
    )
    drifted = ros.ssh_cmd(f"{FILTER} print")
    assert_order(
        drifted,
        "routnix-test-ordered-web",
        "routnix-test-ordered-icmp",
        "routnix-test-ordered-ssh",
        context=f"{FILTER} print (after manual drift, sanity check)",
    )

    import_config(ros, rsc_dir, "ordered_basic")

    restored = ros.ssh_cmd(f"{FILTER} print")
    assert_order(
        restored,
        "routnix-test-ordered-icmp",
        "routnix-test-ordered-ssh",
        "routnix-test-ordered-web",
        "routnix-test-ordered-drop",
        context=f"{FILTER} print (after reapply, order restored)",
    )
    assert_eq(count_only(ros, FILTER), 4, context=f"{FILTER} count after reorder")


def test_ordered_edit(ros: RouterOsMachine, rsc_dir: Path) -> None:
    """Editing a declared item's fields converges via add-new +
    prune-old (identity is the item's whole field set), not an
    in-place `set`."""
    import_config(ros, rsc_dir, "ordered_edit")
    out = ros.ssh_cmd(f"{FILTER} print")
    assert_contains(out, "dst-port=9090", context=f"{FILTER} print after edit")
    assert_not_contains(out, "dst-port=8080", context=f"{FILTER} print after edit (stale entry pruned)")
    assert_eq(count_only(ros, FILTER), 4, context=f"{FILTER} count after edit (no duplicate)")


def test_ordered_ignore(ros: RouterOsMachine, rsc_dir: Path) -> None:
    """`ignore` protects hand-managed entries from the mandatory prune
    sweep; multiple `ignore` predicates each contribute their own
    matches to the same exemption, not just the first one declared;
    anything else not declared is still removed -- including whatever
    ordered_edit.nix left behind."""
    ros.ssh_cmd(f'{FILTER} add chain=input action=accept comment="routnix-test-ordered-keep"')
    ros.ssh_cmd(f'{FILTER} add chain=input action=accept comment="routnix-test-ordered-keep-2"')
    ros.ssh_cmd(f'{FILTER} add chain=input action=accept comment="routnix-test-ordered-manual"')

    import_config(ros, rsc_dir, "ordered_ignore")

    out = ros.ssh_cmd(f"{FILTER} print")
    assert_contains(
        out,
        "routnix-test-ordered-icmp",
        "routnix-test-ordered-keep",
        "routnix-test-ordered-keep-2",
        context=f"{FILTER} print after ignore",
    )
    assert_not_contains(
        out,
        "routnix-test-ordered-manual",
        "routnix-test-ordered-ssh",
        "routnix-test-ordered-web",
        "routnix-test-ordered-drop",
        context=f"{FILTER} print after ignore (unignored/undeclared entries pruned)",
    )
    assert_eq(count_only(ros, FILTER), 3, context=f"{FILTER} count after ignore")

    # Leave the path clean for anything that might run after this.
    ros.ssh_cmd(f"{FILTER} remove [find]")


def test_ordered_ignore_overlap(ros: RouterOsMachine, rsc_dir: Path) -> None:
    """An `ignore`d entry that matches a declared item's derived `find`
    (because that item doesn't set the field the `ignore` predicate
    keys on, e.g. `comment`) must stay distinguishable from that item's
    own entry once routnix creates it alongside -- reapplying must not
    hit "find matched more than one entry"."""
    ros.ssh_cmd(
        f'{FILTER} add chain=input action=accept protocol=icmp '
        f'comment="routnix-test-ordered-ignore-overlap"'
    )

    import_config(ros, rsc_dir, "ordered_ignore_overlap")
    assert_eq(count_only(ros, FILTER), 2, context=f"{FILTER} count after first apply")

    # Reapplying must still tell the ignored entry and the declared
    # item's own entry apart, even though both now match
    # chain=input action=accept protocol=icmp.
    import_config(ros, rsc_dir, "ordered_ignore_overlap")
    assert_contains(
        ros.ssh_cmd(f"{FILTER} print"),
        "routnix-test-ordered-ignore-overlap",
        context=f"{FILTER} print after reapply",
    )
    assert_eq(count_only(ros, FILTER), 2, context=f"{FILTER} count after reapply (no duplicate)")

    ros.ssh_cmd(f"{FILTER} remove [find]")


def test_ordered_prune_empty(ros: RouterOsMachine, rsc_dir: Path) -> None:
    """Regression: kind = "ordered" prunes unconditionally, even with
    an empty `items` list -- declaring no items for a path must still
    remove everything already there, not leave the path untouched."""
    ros.ssh_cmd(f'{FILTER} add chain=input action=accept comment="routnix-test-ordered-empty-manual"')

    import_config(ros, rsc_dir, "ordered_prune_empty")

    assert_eq(count_only(ros, FILTER), 0, context=f"{FILTER} count after applying empty ordered items")


def test_unordered_add(ros: RouterOsMachine, rsc_dir: Path) -> None:
    """kind = "unordered": a missing item is added."""
    import_config(ros, rsc_dir, "unordered_basic")
    out = ros.ssh_cmd(f'{ADDRESS_LIST} print where list="routnix-test-basic"')
    assert_contains(out, "10.10.10.10", context=f"{ADDRESS_LIST} print (routnix-test-basic)")
    assert_eq(count_only(ros, ADDRESS_LIST, 'list="routnix-test-basic"'), 1)


def test_unordered_idempotent(ros: RouterOsMachine, rsc_dir: Path) -> None:
    """Reapplying must not duplicate the entry."""
    import_config(ros, rsc_dir, "unordered_basic")
    assert_eq(count_only(ros, ADDRESS_LIST, 'list="routnix-test-basic"'), 1)
    ros.ssh_cmd(f'{ADDRESS_LIST} remove [find where list="routnix-test-basic"]')


def test_unordered_find_fields(ros: RouterOsMachine, rsc_dir: Path) -> None:
    """Derived `find` distinguishes an item that sets a field (rendered
    as `k=v`) from one that doesn't (rendered as `!k`) -- they must not
    collapse into a single entry."""
    import_config(ros, rsc_dir, "unordered_find_fields")
    out = ros.ssh_cmd(f'{ADDRESS_LIST} print where list="routnix-test-fields"')
    assert_contains(out, "10.10.10.30", "10.10.10.31", context=f"{ADDRESS_LIST} print (routnix-test-fields)")
    assert_eq(count_only(ros, ADDRESS_LIST, 'list="routnix-test-fields"'), 2)
    ros.ssh_cmd(f'{ADDRESS_LIST} remove [find where list="routnix-test-fields"]')


def test_unordered_prune(ros: RouterOsMachine, rsc_dir: Path) -> None:
    """kind = "unordered" always removes entries not covered by a
    current item's `find` or by `ignore`; an `ignore`d entry survives."""
    ros.ssh_cmd(
        f'{ADDRESS_LIST} add address=10.10.10.21 list="routnix-test-prune" '
        f'comment="routnix-test-prune-keep"'
    )
    ros.ssh_cmd(
        f'{ADDRESS_LIST} add address=10.10.10.22 list="routnix-test-prune" '
        f'comment="routnix-test-prune-manual"'
    )

    import_config(ros, rsc_dir, "unordered_prune")

    out = ros.ssh_cmd(f'{ADDRESS_LIST} print where list="routnix-test-prune"')
    assert_contains(out, "10.10.10.20", "routnix-test-prune-keep", context=f"{ADDRESS_LIST} print after prune")
    assert_not_contains(out, "routnix-test-prune-manual", context=f"{ADDRESS_LIST} print after prune")
    assert_eq(count_only(ros, ADDRESS_LIST, 'list="routnix-test-prune"'), 2)

    ros.ssh_cmd(f'{ADDRESS_LIST} remove [find where list="routnix-test-prune"]')


def test_unordered_prune_empty(ros: RouterOsMachine, rsc_dir: Path) -> None:
    """Regression: kind = "unordered" prunes unconditionally, even
    with an empty `items` list -- declaring no items for a path must
    still remove everything already there, not leave the path
    untouched."""
    ros.ssh_cmd(
        f'{ADDRESS_LIST} add address=10.10.10.60 list="routnix-test-empty" '
        f'comment="routnix-test-unordered-empty-manual"'
    )

    import_config(ros, rsc_dir, "unordered_prune_empty")

    assert_eq(count_only(ros, ADDRESS_LIST), 0, context=f"{ADDRESS_LIST} count after applying empty unordered items")


def test_settings_apply(ros: RouterOsMachine, rsc_dir: Path) -> None:
    """kind = "settings": a single `set` of the declared fields."""
    import_config(ros, rsc_dir, "settings_basic")
    out = ros.ssh_cmd("/system identity print")
    assert_contains(out, "routnix-test-router", context="/system identity print")


def test_settings_idempotent(ros: RouterOsMachine, rsc_dir: Path) -> None:
    """Reapplying a `set` of the same fields is a no-op, not an error."""
    import_config(ros, rsc_dir, "settings_basic")
    out = ros.ssh_cmd("/system identity print")
    assert_contains(out, "routnix-test-router", context="/system identity print (reapply)")


def test_effect_add(ros: RouterOsMachine, rsc_dir: Path) -> None:
    """kind = "effect": `create` runs custom .rsc text (not a plain
    `add`), guarded by `find`; a line targeting a different absolute
    path doesn't permanently change the entry's own path context."""
    import_config(ros, rsc_dir, "effect_basic")
    out = ros.ssh_cmd(f'{ADDRESS_LIST} print where list="routnix-test-effect"')
    assert_contains(
        out,
        "10.10.10.40", "routnix-test-effect-1",
        "10.10.10.41", "routnix-test-effect-2",
        context=f"{ADDRESS_LIST} print (routnix-test-effect)",
    )
    assert_eq(count_only(ros, ADDRESS_LIST, 'list="routnix-test-effect"'), 2)
    note = ros.ssh_cmd("/system note print")
    assert_contains(note, "routnix-test-effect-note-2", context="/system note print (last item's side effect)")


def test_effect_idempotent(ros: RouterOsMachine, rsc_dir: Path) -> None:
    """Reapplying must not rerun `create` (or its side effects) for
    items `find` already matches."""
    import_config(ros, rsc_dir, "effect_basic")
    assert_eq(count_only(ros, ADDRESS_LIST, 'list="routnix-test-effect"'), 2)
    note = ros.ssh_cmd("/system note print")
    assert_contains(note, "routnix-test-effect-note-2", context="/system note print (unchanged on reapply)")

    ros.ssh_cmd(f'{ADDRESS_LIST} remove [find where list="routnix-test-effect"]')
    ros.ssh_cmd('/system note set note=""')


def test_effect_prune(ros: RouterOsMachine, rsc_dir: Path) -> None:
    """kind = "effect" always removes entries not covered by a current
    item's `find` or by `ignore`, the same as kind = "unordered"; the
    declared item's id for the sweep is resolved by re-`find`ing after
    `create` runs, since `create` here isn't a plain `add`."""
    ros.ssh_cmd(
        f'{ADDRESS_LIST} add address=10.10.10.51 list="routnix-test-effect-prune" '
        f'comment="routnix-test-effect-prune-keep"'
    )
    ros.ssh_cmd(
        f'{ADDRESS_LIST} add address=10.10.10.52 list="routnix-test-effect-prune" '
        f'comment="routnix-test-effect-prune-manual"'
    )

    import_config(ros, rsc_dir, "effect_prune")

    out = ros.ssh_cmd(f'{ADDRESS_LIST} print where list="routnix-test-effect-prune"')
    assert_contains(
        out, "10.10.10.50", "routnix-test-effect-prune-keep",
        context=f"{ADDRESS_LIST} print after prune",
    )
    assert_not_contains(out, "routnix-test-effect-prune-manual", context=f"{ADDRESS_LIST} print after prune")
    assert_eq(count_only(ros, ADDRESS_LIST, 'list="routnix-test-effect-prune"'), 2)
    note = ros.ssh_cmd("/system note print")
    assert_contains(note, "routnix-test-effect-prune-note", context="/system note print (create's side effect)")

    ros.ssh_cmd(f'{ADDRESS_LIST} remove [find where list="routnix-test-effect-prune"]')
    ros.ssh_cmd('/system note set note=""')


def test_effect_prune_empty(ros: RouterOsMachine, rsc_dir: Path) -> None:
    """Regression: kind = "effect" prunes unconditionally, even with
    an empty `items` list -- declaring no items for a path must still
    remove everything already there, not leave the path untouched."""
    ros.ssh_cmd(
        f'{ADDRESS_LIST} add address=10.10.10.61 list="routnix-test-empty" '
        f'comment="routnix-test-effect-empty-manual"'
    )

    import_config(ros, rsc_dir, "effect_prune_empty")

    assert_eq(count_only(ros, ADDRESS_LIST), 0, context=f"{ADDRESS_LIST} count after applying empty effect items")


def test_inventory_configure(ros: RouterOsMachine, rsc_dir: Path) -> None:
    """kind = "inventory": a hardware-bound entry that already exists (an
    ethernet interface) is located by `find` and adjusted in place (its
    comment set), with nothing added or removed."""
    before = count_only(ros, ETHERNET)
    import_config(ros, rsc_dir, "inventory_basic")
    out = ros.ssh_cmd(f"{ETHERNET} print detail")
    assert_contains(out, "routnix-test-inventory", context=f"{ETHERNET} print detail")
    # inventory never prunes: the interface set is unchanged.
    assert_eq(count_only(ros, ETHERNET), before, context=f"{ETHERNET} count after inventory_basic")


def test_inventory_idempotent(ros: RouterOsMachine, rsc_dir: Path) -> None:
    """Reapplying converges on the same comment without error, and (since
    inventory can't add) without duplicating anything."""
    before = count_only(ros, ETHERNET)
    import_config(ros, rsc_dir, "inventory_basic")
    out = ros.ssh_cmd(f"{ETHERNET} print detail")
    assert_contains(out, "routnix-test-inventory", context=f"{ETHERNET} print detail (reapply)")
    assert_eq(count_only(ros, ETHERNET), before, context=f"{ETHERNET} count after reapply")

    ros.ssh_cmd(f'{ETHERNET} set [find where comment="routnix-test-inventory"] comment=""')


# The "users_*" group shares state across its subtests the same way the
# "ordered_*" group does: each relies on the router state the previous
# one left behind. Every config in this group declares `admin` with
# `create = false`, since it's the account routeros_test.py itself
# connects over SSH as -- if `/user`'s mandatory prune sweep ever
# removed it, every subsequent SSH command (in this group and beyond)
# would fail, which itself would surface a regression here loudly.


def test_users_add(ros: RouterOsMachine, rsc_dir: Path) -> None:
    """The `users` module: a declared user is added; `admin` (the
    test's own account) is untouched."""
    import_config(ros, rsc_dir, "users_basic")
    out = ros.ssh_cmd(f"{USER} print")
    assert_contains(out, "admin", "testuser", context=f"{USER} print")
    assert_eq(count_only(ros, USER), 2, context=f"{USER} count after users_basic")


def test_users_idempotent(ros: RouterOsMachine, rsc_dir: Path) -> None:
    """Reapplying must not duplicate the declared user or touch admin."""
    import_config(ros, rsc_dir, "users_basic")
    assert_eq(count_only(ros, USER), 2, context=f"{USER} count after reapplying users_basic")


def test_users_prune(ros: RouterOsMachine, rsc_dir: Path) -> None:
    """`/user`'s mandatory prune sweep removes an undeclared account
    while leaving `admin` (`create = false`, `ignore`d) and the
    declared `testuser` alone."""
    ros.ssh_cmd(f'{USER} add name=routnix-test-users-manual group=full password=""')

    import_config(ros, rsc_dir, "users_basic")

    out = ros.ssh_cmd(f"{USER} print")
    assert_contains(out, "admin", "testuser", context=f"{USER} print after prune")
    assert_not_contains(out, "routnix-test-users-manual", context=f"{USER} print after prune")
    assert_eq(count_only(ros, USER), 2, context=f"{USER} count after prune")

    ros.ssh_cmd(f'{USER} remove [find where name="testuser"]')


def test_users_ssh_keys_add(ros: RouterOsMachine, rsc_dir: Path) -> None:
    """A declared user's `sshPubKeys` are added; `admin`'s keys (left
    at the default `null`) are untouched."""
    import_config(ros, rsc_dir, "users_ssh_keys_basic")
    assert_eq(
        count_only(ros, USER_SSH_KEYS, 'user="keyuser"'), 1,
        context=f"{USER_SSH_KEYS} count for keyuser",
    )
    assert_eq(
        count_only(ros, USER_SSH_KEYS, 'user="admin"'), 0,
        context=f"{USER_SSH_KEYS} count for admin (untouched)",
    )


def test_users_ssh_keys_idempotent(ros: RouterOsMachine, rsc_dir: Path) -> None:
    """Reapplying must not rerun `create` (or duplicate the key) for a
    user `find` already matches."""
    import_config(ros, rsc_dir, "users_ssh_keys_basic")
    assert_eq(
        count_only(ros, USER_SSH_KEYS, 'user="keyuser"'), 1,
        context=f"{USER_SSH_KEYS} count for keyuser (reapply)",
    )


def test_users_ssh_keys_wipe(ros: RouterOsMachine, rsc_dir: Path) -> None:
    """Regression: `sshPubKeys = [ ]` is a real declaration ("this user
    should have no keys"), distinct from `null` ("don't touch this
    user's keys") -- it must fully manage (and here, wipe) keyuser's
    keys, not leave the previously-added one in place."""
    import_config(ros, rsc_dir, "users_ssh_keys_empty")
    assert_eq(
        count_only(ros, USER_SSH_KEYS, 'user="keyuser"'), 0,
        context=f"{USER_SSH_KEYS} count for keyuser after wiping",
    )

    ros.ssh_cmd(f'{USER} remove [find where name="keyuser"]')


def test_users_existing_user_keys(ros: RouterOsMachine, rsc_dir: Path) -> None:
    """`create` only controls account creation: a `create = false`
    user's declared `sshPubKeys` are still fully managed, even for an
    account routnix itself never created. Deliberately not `admin`:
    attaching a key to it would make RouterOS require key-based auth
    for that account, breaking the test's own password-based SSH
    access for every subtest after this one."""
    ros.ssh_cmd('/user add name=routnix-test-existinguser group=full password=""')

    import_config(ros, rsc_dir, "users_existing_user_keys")

    assert_eq(
        count_only(ros, USER_SSH_KEYS, 'user="routnix-test-existinguser"'), 1,
        context=f"{USER_SSH_KEYS} count for routnix-test-existinguser",
    )
    assert_eq(count_only(ros, USER), 2, context=f"{USER} count (admin + existinguser)")

    ros.ssh_cmd(f'{USER} remove [find where name="routnix-test-existinguser"]')


# The "firewall_*" group runs last: firewall_basic.nix's mandatory
# prune sweep clears the whole /ip firewall filter table and reinstates
# only the rules it declares (including tcp/22, so this test's own SSH
# access survives). It must not run before the "ordered_*" group, whose
# assertions rely on its own table contents.


def test_firewall_filter_block_ordering(ros: RouterOsMachine, rsc_dir: Path) -> None:
    """The `firewall.filter` module: named blocks compile down to a
    single kind = "ordered" /ip firewall filter table, ordered by
    block-level `before`/`after`, so the declared rules land in the
    intended order."""
    import_config(ros, rsc_dir, "firewall_basic")
    out = ros.ssh_cmd(f"{FILTER} print")
    assert_order(
        out,
        "routnix-test-fw-established",
        "routnix-test-fw-ssh",
        "routnix-test-fw-icmp",
        "routnix-test-fw-drop",
        context=f"{FILTER} print after firewall_basic",
    )
    assert_eq(count_only(ros, FILTER), 4, context=f"{FILTER} count after firewall_basic")


def test_firewall_filter_idempotent(ros: RouterOsMachine, rsc_dir: Path) -> None:
    """Reapplying the module-generated table must not duplicate rules."""
    import_config(ros, rsc_dir, "firewall_basic")
    assert_eq(count_only(ros, FILTER), 4, context=f"{FILTER} count after reapplying firewall_basic")


# Ordering matters within the "ordered_*" and "users_*" groups -- each
# builds on the router state the previous one left behind. Everything
# else is independent and self-cleaning.
SUBTESTS: list[tuple[str, Callable[[RouterOsMachine, Path], None]]] = [
    ("ordered_add", test_ordered_add),
    ("ordered_idempotent", test_ordered_idempotent),
    ("ordered_reorder", test_ordered_reorder),
    ("ordered_edit", test_ordered_edit),
    ("ordered_ignore", test_ordered_ignore),
    ("ordered_ignore_overlap", test_ordered_ignore_overlap),
    ("ordered_prune_empty", test_ordered_prune_empty),
    ("unordered_add", test_unordered_add),
    ("unordered_idempotent", test_unordered_idempotent),
    ("unordered_find_fields", test_unordered_find_fields),
    ("unordered_prune", test_unordered_prune),
    ("unordered_prune_empty", test_unordered_prune_empty),
    ("settings_apply", test_settings_apply),
    ("settings_idempotent", test_settings_idempotent),
    ("effect_add", test_effect_add),
    ("effect_idempotent", test_effect_idempotent),
    ("effect_prune", test_effect_prune),
    ("effect_prune_empty", test_effect_prune_empty),
    ("inventory_configure", test_inventory_configure),
    ("inventory_idempotent", test_inventory_idempotent),
    ("users_add", test_users_add),
    ("users_idempotent", test_users_idempotent),
    ("users_prune", test_users_prune),
    ("users_ssh_keys_add", test_users_ssh_keys_add),
    ("users_ssh_keys_idempotent", test_users_ssh_keys_idempotent),
    ("users_ssh_keys_wipe", test_users_ssh_keys_wipe),
    ("users_existing_user_keys", test_users_existing_user_keys),
    ("firewall_filter_block_ordering", test_firewall_filter_block_ordering),
    ("firewall_filter_idempotent", test_firewall_filter_idempotent),
]


def main() -> None:
    args = parse_args()

    with tempfile.TemporaryDirectory() as _tmp:
        tmp_dir = Path(_tmp)
        out_dir = Path(args.out_dir)
        out_dir.mkdir(parents=True, exist_ok=True)
        rsc_dir = Path(args.rsc_dir)

        ros = RouterOsMachine(
            qemu_bin=args.qemu,
            image_path=args.image,
            name="routeros",
            ssh_port=args.ssh_port,
            ssh_bin=args.ssh,
            scp_bin=args.scp,
            tmp_dir=tmp_dir,
            out_dir=out_dir,
            logger=TerminalLogger(),
        )

        log = ros.logger
        boot_failure: Exception | None = None
        results: list[tuple[str, Exception | None]] = []

        try:
            with log.nested("boot RouterOS CHR"):
                ros.start()
            with log.nested("wait for SSH"):
                ros.wait_for_ssh()

            for subtest_name, subtest_fn in SUBTESTS:
                with log.nested(f"subtest: {subtest_name}"):
                    try:
                        subtest_fn(ros, rsc_dir)
                    except Exception as exc:  # noqa: BLE001 -- collected, not swallowed
                        print(f"FAIL: {subtest_name}: {exc}", file=sys.stderr)
                        traceback.print_exc()
                        results.append((subtest_name, exc))
                    else:
                        print(f"PASS: {subtest_name}")
                        results.append((subtest_name, None))
        except Exception as exc:  # boot/SSH-level failure: no subtests could run
            boot_failure = exc
        finally:
            # release() before reading the console log, so the serial
            # thread has been joined and the log is fully populated.
            ros.release()

        failed = [(n, e) for n, e in results if e is not None]

        print("\n=== routnix integration test summary ===")
        for subtest_name, _ in SUBTESTS:
            outcome = next((e for n, e in results if n == subtest_name), "SKIPPED")
            status = "PASS" if outcome is None else ("SKIPPED" if outcome == "SKIPPED" else "FAIL")
            print(f"  [{status}] {subtest_name}")
        print("=========================================\n")

        if boot_failure is not None or failed:
            print("\n=== RouterOS console log ===", file=sys.stderr)
            print(ros.get_console_log(), file=sys.stderr)
            print("=== end console log ===\n", file=sys.stderr)
            if boot_failure is not None:
                raise SystemExit(f"FAIL: could not boot/reach RouterOS: {boot_failure}") from boot_failure
            raise SystemExit(
                f"FAIL: {len(failed)}/{len(SUBTESTS)} subtest(s) failed: "
                + ", ".join(n for n, _ in failed)
            )

        # Only reached on full success. Leave the console log behind so a
        # passing build has something inspectable.
        (out_dir / "console.log").write_text(ros.get_console_log())
        shutil.copytree(rsc_dir, out_dir / "routnix-test-configs")


if __name__ == "__main__":
    main()
