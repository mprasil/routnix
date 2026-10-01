{
  lib,
  pkgs,
}: let
  routnix = import ../../lib/default.nix {inherit lib;};

  # Evaluates a small inline top-level module (e.g. `{ users.enable =
  # true; ... }`) through the full `evalConfig` pipeline and returns the
  # resulting `config` attrset. `lib/tests/` already covers
  # `lib/render_rsc.nix`'s rendering of `routeros.config` into `.rsc`
  # text, so these tests stay focused on each module's own option ->
  # config logic.
  evalConfigFull = module: (routnix.evalConfig {modules = [module];}).config;

  # Just the `routeros.config` subtree, what a module compiles its
  # options down to, *before* rendering.
  evalConfig = module: (evalConfigFull module).routeros.config;

  # Strips a `routeros.config.<path>` entry down to its plain-data
  # fields for comparison -- `find`/`create` are functions and can't go
  # through `lib.runTests`'s `==`.
  dataFields = entry: {inherit (entry) kind items ignore;};

  throws = expr: !(builtins.tryEval (builtins.deepSeq expr true)).success;

  diffFailures = f: let
    toDiffableString = v:
      if builtins.typeOf v == "string"
      then v
      else lib.generators.toPretty {} v;
  in
    builtins.readFile (
      pkgs.runCommand "diff-error" {} ''
        cat > expected.txt <<'ENDOFTESTSTRING'
        ${toDiffableString f.expected}
        ENDOFTESTSTRING
        cat > got.txt <<'ENDOFTESTSTRING'
        ${toDiffableString f.result}
        ENDOFTESTSTRING
        echo "#### FAILED TEST: ${f.name}" > $out
        echo "## Test Result:" >> $out
        cat got.txt >> $out
        echo >> $out
        echo "## Difference:" >> $out
        ${pkgs.diffutils}/bin/diff \
          --color=always \
          --label "Test Result" \
          --label "Expected" \
          -u  got.txt expected.txt >> "$out" || true
      ''
    );

  # Arguments handed to every sibling test file in this directory.
  testFileArgs = {
    inherit lib evalConfig evalConfigFull dataFields throws;
  };

  # Every `*.nix` file in this directory other than this one is a
  # fragment of the overall `tests` attrset -- dropping a new file in
  # here is enough to have it picked up, no separate list to maintain.
  testFileNames =
    builtins.attrNames
    (lib.filterAttrs
      (name: type: type == "regular" && name != "default.nix" && lib.hasSuffix ".nix" name)
      (builtins.readDir ./.));

  tests =
    lib.foldl'
    (acc: name: acc // import (./. + "/${name}") testFileArgs)
    {}
    testFileNames;

  failures = lib.runTests tests;
in
  if failures == []
  then null
  else
    throw ''
      routnix: ${toString (builtins.length failures)} modules/tests test(s) failed:
      ${lib.concatMapStringsSep "\n\n" diffFailures failures}
    ''
