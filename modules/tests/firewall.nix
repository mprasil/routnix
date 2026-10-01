{
  evalConfig,
  evalConfigFull,
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

  # -- per-family emission --------------------------------------------

  # `family` defaults to `"both"`: a block's rules land in both tables.
  testBlockDefaultFamilyIsBoth = let
    cfg' = evalConfig {
      firewall.filter.enable = true;
      firewall.filter.rules.allowSsh = {
        chain = "input";
        rules = [{action = "accept"; comment = "ssh";}];
      };
    };
  in {
    expr = {
      ipv4 = ruleComments cfg'."/ip firewall filter";
      ipv6 = ruleComments cfg'."/ipv6 firewall filter";
    };
    expected = {
      ipv4 = ["ssh"];
      ipv6 = ["ssh"];
    };
  };

  # `family = "ipv4"` keeps the block's rules out of `/ipv6 firewall
  # filter`, which is still managed (and so pruned to empty).
  testBlockFamilyIpv4StaysOutOfIpv6Table = let
    cfg' = evalConfig {
      firewall.filter.enable = true;
      firewall.filter.rules.allowSsh = {
        family = "ipv4";
        chain = "input";
        rules = [{action = "accept"; comment = "ssh";}];
      };
    };
  in {
    expr = {
      ipv4 = ruleComments cfg'."/ip firewall filter";
      ipv6 = ruleComments cfg'."/ipv6 firewall filter";
    };
    expected = {
      ipv4 = ["ssh"];
      ipv6 = [];
    };
  };

  # `family = "ipv6"` keeps the block's rules out of `/ip firewall
  # filter`, which is still managed (and so pruned to empty).
  testBlockFamilyIpv6StaysOutOfIpv4Table = let
    cfg' = evalConfig {
      firewall.filter.enable = true;
      firewall.filter.rules.allowIcmp6 = {
        family = "ipv6";
        chain = "input";
        rules = [{action = "accept"; comment = "icmp6";}];
      };
    };
  in {
    expr = {
      ipv4 = ruleComments cfg'."/ip firewall filter";
      ipv6 = ruleComments cfg'."/ipv6 firewall filter";
    };
    expected = {
      ipv4 = [];
      ipv6 = ["icmp6"];
    };
  };

  # Blocks of different families keep their relative order within the
  # table they land in. `after` edges (across families here) pin the
  # block order, since blocks with no ordering edge between them may
  # fall in either order.
  testFamilyFilteringPreservesBlockOrder = let
    cfg' = evalConfig {
      firewall.filter.enable = true;
      firewall.filter.rules = {
        a4 = {
          family = "ipv4";
          chain = "input";
          rules = [{action = "accept"; comment = "a4";}];
        };
        b6 = {
          family = "ipv6";
          after = ["a4"];
          chain = "input";
          rules = [{action = "accept"; comment = "b6";}];
        };
        c4 = {
          family = "ipv4";
          after = ["b6"];
          chain = "input";
          rules = [{action = "accept"; comment = "c4";}];
        };
        d6 = {
          family = "ipv6";
          after = ["c4"];
          chain = "input";
          rules = [{action = "accept"; comment = "d6";}];
        };
      };
    };
  in {
    expr = {
      ipv4 = ruleComments cfg'."/ip firewall filter";
      ipv6 = ruleComments cfg'."/ipv6 firewall filter";
    };
    expected = {
      ipv4 = ["a4" "c4"];
      ipv6 = ["b6" "d6"];
    };
  };

  # `firewall.filter.family` is the default for blocks that don't set
  # their own, and a block may still override it.
  testModuleFamilyIsDefaultForBlocks = let
    cfg' = evalConfig {
      firewall.filter.enable = true;
      firewall.filter.family = "ipv6";
      firewall.filter.rules.omit = {
        chain = "input";
        rules = [{action = "accept"; comment = "from-module";}];
      };
      firewall.filter.rules.override = {
        family = "ipv4";
        chain = "input";
        rules = [{action = "accept"; comment = "overridden";}];
      };
    };
  in {
    expr = {
      ipv4 = ruleComments cfg'."/ip firewall filter";
      ipv6 = ruleComments cfg'."/ipv6 firewall filter";
    };
    expected = {
      ipv4 = ["overridden"];
      ipv6 = ["from-module"];
    };
  };

  # `"ipv4only"` manages only `/ip firewall filter`.
  testModuleFamilyIpv4OnlyManagesIpv4TableOnly = let
    cfg' = evalConfig {
      firewall.filter.enable = true;
      firewall.filter.family = "ipv4only";
      firewall.filter.rules.allowSsh = {
        chain = "input";
        rules = [{action = "accept"; comment = "ssh";}];
      };
    };
  in {
    expr = {
      hasIpv6 = cfg' ? "/ipv6 firewall filter";
      ipv4 = ruleComments cfg'."/ip firewall filter";
    };
    expected = {
      hasIpv6 = false;
      ipv4 = ["ssh"];
    };
  };

  # `"ipv4only"` rejects a block that targets ipv6.
  testModuleFamilyIpv4OnlyRejectsIpv6Block = {
    expr = throws ((evalConfig {
        firewall.filter.enable = true;
        firewall.filter.family = "ipv4only";
        firewall.filter.rules.allowIcmp6 = {
          family = "ipv6";
          chain = "input";
        };
      })."/ip firewall filter");
    expected = true;
  };

  # Enabling with no blocks manages both tables.
  testEnabledWithNoBlocksManagesBothTables = let
    cfg' = evalConfig {firewall.filter.enable = true;};
  in {
    expr = {
      ipv4 = dataFields cfg'."/ip firewall filter";
      ipv6 = dataFields cfg'."/ipv6 firewall filter";
    };
    expected = {
      ipv4 = {kind = "ordered"; items = []; ignore = [];};
      ipv6 = {kind = "ordered"; items = []; ignore = [];};
    };
  };

  # -- RouterOS v6 ipv6 precondition ----------------------------------

  # On v7 ipv6 is always available, so no precondition.
  testNoIpv6PreCheckOnV7 = {
    expr = (evalConfigFull {
        device.platform = "routeros_v7";
        firewall.filter.enable = true;
        firewall.filter.rules.allowSsh = {
          chain = "input";
          rules = [{action = "accept"; comment = "ssh";}];
        };
      })
      .routeros.preCheck;
    expected = "";
  };

  # On v6 the managed ipv6 table is guarded by a package check.
  testIpv6PreCheckOnV6 = {
    expr = lib.hasInfix "name=\"ipv6\" disabled=no" (evalConfigFull {
        device.platform = "routeros_v6";
        firewall.filter.enable = true;
        firewall.filter.rules.allowSsh = {
          chain = "input";
          rules = [{action = "accept"; comment = "ssh";}];
        };
      })
      .routeros.preCheck;
    expected = true;
  };

  # `"ipv4only"` never manages ipv6, so no precondition on v6 either.
  testNoIpv6PreCheckOnV6WithIpv4Only = {
    expr = (evalConfigFull {
        device.platform = "routeros_v6";
        firewall.filter.enable = true;
        firewall.filter.family = "ipv4only";
      })
      .routeros.preCheck;
    expected = "";
  };

  # Disabled: nothing is managed, including the precondition.
  testNoIpv6PreCheckWhenDisabled = {
    expr = (evalConfigFull {
        device.platform = "routeros_v6";
        firewall.filter.rules.allowSsh = {
          chain = "input";
          rules = [{action = "accept"; comment = "ssh";}];
        };
      })
      .routeros.preCheck;
    expected = "";
  };
}