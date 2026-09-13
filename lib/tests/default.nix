{
  lib,
  pkgs,
}: let
  inherit (import ../render_rsc/common.nix {inherit lib;}) renderValue renderArgs renderQuery;
  inherit (import ../render_rsc/unordered.nix {inherit lib;}) deriveFind;
  routnix = import ../default.nix {inherit lib;};

  # Evaluates a small inline `routeros.config` module through the full
  # `evalConfig` pipeline (module eval -> toposort -> render).
  eval = module: routnix.evalConfig {modules = [module];};
  rsc = module: (eval module).rsc;

  # True iff fully evaluating `expr` throws.
  throws = expr: !(builtins.tryEval (builtins.deepSeq expr true)).success;

  # Format failures nicely
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
    inherit lib routnix eval rsc throws renderValue renderArgs renderQuery deriveFind;
  };

  # Every `*.nix` file in this directory other than this one is a fragment
  # of the overall `tests` attrset -- dropping a new file in here is
  # enough to have it picked up, no separate list to maintain.
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
      routnix: ${toString (builtins.length failures)} lib/tests test(s) failed:
      ${lib.concatMapStringsSep "\n\n" diffFailures failures}
    ''
