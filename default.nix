{
  pkgs ? import <nixpkgs> {
    config = { };
    overlays = [ ];
  },
  configuration,
}:

let
  evaluated = pkgs.lib.evalModules {
    modules = [
      ./openwrt
      configuration
    ];
    specialArgs = {
      inherit pkgs;
    };
  };
in

pkgs.buildEnv rec {
  name = "dewclaw-env";

  paths = builtins.attrValues passthru.targets;

  passthru.targets = pkgs.lib.mapAttrs (_: dev: dev.build.deploy) evaluated.config.openwrt;
}
