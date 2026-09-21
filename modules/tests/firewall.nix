{
  evalConfig,
  dataFields,
  throws,
  lib,
  ...
}: let
  # Deployment only looks at each rule's `comment`, so expected values
  # below stay decoupled from the rest of a rule's fields.
  ruleComments = entry: map (rule: rule.comment) entry.items;
  ruleChains = entry: map (rule: rule.chain) entry.items;
in {
  testDisabledByDefaultDeclaresNothing = {
    expr = evalConfig {
      firewall.filter.rules.allowSsh = {
        chain = "input";
        rules = [{protocol = "tcp"; "dst-port" = 22; action = "accept";}];
      };
    };
    expected = {};
  };

  # Enabling with no blocks still manages the table (kind = "ordered"
  # prunes unconditionally), so the path must be present with empty
  # `items`.
  testEnabledWithNoBlocksManagesFilterEmpty = {
    expr = dataFields (evalConfig {firewall.filter.enable = true;})."/ip firewall filter";
    expected = {
      kind = "ordered";
      items = [];
      ignore = [];
    };
  };

  # The motivating case: a shared prerequisite block, then blocks that
  # depend on it, with each block's own rules kept in declared order.
  testBlocksOrderedByAfterAndRuleOrderPreserved = let
    entry = (evalConfig {
      firewall.filter.enable = true;
      firewall.filter.rules = {
        allowEstablished = {
          chain = "input";
          rules = [
            {
              action = "accept";
              "connection-state" = "established,related";
              comment = "established";
            }
          ];
        };
        allowDns = {
          after = ["allowEstablished"];
          chain = "input";
          rules = [
            {
              protocol = "tcp";
              "dst-port" = 53;
              action = "accept";
              comment = "dns-tcp";
            }
            {
              protocol = "udp";
              "dst-port" = 53;
              action = "accept";
              comment = "dns-udp";
            }
          ];
        };
        allowSsh = {
          after = ["allowDns"];
          chain = "input";
          rules = [
            {
              protocol = "tcp";
              "dst-port" = 22;
              action = "accept";
              comment = "ssh";
            }
          ];
        };
      };
    })."/ip firewall filter";
  in {
    expr = {
      inherit (entry) kind;
      comments = ruleComments entry;
    };
    expected = {
      kind = "ordered";
      comments = ["established" "dns-tcp" "dns-udp" "ssh"];
    };
  };

  # `before` is the mirror of `after`: the block listing another block
  # in `before` is emitted first.
  testBlockBeforeOrdersEarlier = let
    entry = (evalConfig {
      firewall.filter.enable = true;
      firewall.filter.rules = {
        first = {
          before = ["second"];
          chain = "input";
          rules = [{action = "accept"; comment = "first";}];
        };
        second = {
          chain = "input";
          rules = [{action = "drop"; comment = "second";}];
        };
      };
    })."/ip firewall filter";
  in {
    expr = ruleComments entry;
    expected = ["first" "second"];
  };

  # Two blocks with the same prerequisite may fall in either order
  # relative to each other (no edge between them), but both must still
  # land after the prerequisite.
  testBlocksSharingPrerequisiteBothFollowIt = let
    entry = (evalConfig {
      firewall.filter.enable = true;
      firewall.filter.rules = {
        allowEstablished = {
          chain = "input";
          rules = [{action = "accept"; comment = "established";}];
        };
        allowSsh = {
          after = ["allowEstablished"];
          chain = "input";
          rules = [{protocol = "tcp"; "dst-port" = 22; action = "accept"; comment = "ssh";}];
        };
        allowDns = {
          after = ["allowEstablished"];
          chain = "input";
          rules = [{protocol = "udp"; "dst-port" = 53; action = "accept"; comment = "dns";}];
        };
      };
    })."/ip firewall filter";
    comments = ruleComments entry;
  in {
    expr = {
      first = builtins.head comments;
      rest = lib.sort (a: b: a < b) (builtins.tail comments);
    };
    expected = {
      first = "established";
      rest = ["dns" "ssh"];
    };
  };

  # Every rule carries its block's `chain`, and a block's other fields
  # are left untouched.
  testBlockChainAppliedToEveryRule = let
    entry = (evalConfig {
      firewall.filter.enable = true;
      firewall.filter.rules.allowSsh = {
        chain = "forward";
        rules = [
          {protocol = "tcp"; action = "accept"; comment = "a";}
          {protocol = "udp"; action = "accept"; comment = "b";}
        ];
      };
    })."/ip firewall filter";
  in {
    expr = {
      chains = ruleChains entry;
      protocols = map (rule: rule.protocol) entry.items;
    };
    expected = {
      chains = ["forward" "forward"];
      protocols = ["tcp" "udp"];
    };
  };

  testUnknownBeforeAfterReferenceThrows = {
    expr = throws ((evalConfig {
        firewall.filter.enable = true;
        firewall.filter.rules.allowSsh = {
          after = ["nope"];
          chain = "input";
        };
      })."/ip firewall filter");
    expected = true;
  };

  testDependencyCycleThrows = {
    expr = throws ((evalConfig {
        firewall.filter.enable = true;
        firewall.filter.rules = {
          a = {
            after = ["b"];
            chain = "input";
          };
          b = {
            after = ["a"];
            chain = "input";
          };
        };
      })."/ip firewall filter");
    expected = true;
  };

  # `chain` is a block-level concern; a rule may not set it.
  testPerRuleChainThrows = {
    expr = throws ((evalConfig {
        firewall.filter.enable = true;
        firewall.filter.rules.allowSsh = {
          chain = "input";
          rules = [{chain = "output"; action = "accept";}];
        };
      })."/ip firewall filter");
    expected = true;
  };
}