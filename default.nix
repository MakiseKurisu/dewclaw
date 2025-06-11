{
  pkgs ? import <nixpkgs> {
    config = { };
    overlays = [ ];
  },
  configuration,
}:

let
  inherit (pkgs) lib;

  evaluated = lib.evalModules {
    modules = [
      ./openwrt
      configuration
    ];
    specialArgs = {
      inherit pkgs;
    };
  };

  targets = lib.mapAttrs (_: dev: dev.build.deploy) evaluated.config.openwrt;
in

lib.asserts.checkAssertWarn evaluated.config.assertions evaluated.config.warnings (
  pkgs.buildEnv {
    name = "dewclaw-env";

    paths = lib.attrValues targets;

    passthru = { inherit targets; };
  }
)
