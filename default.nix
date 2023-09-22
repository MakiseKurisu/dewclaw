{ pkgs ? import <nixpkgs> { config = {}; overlays = []; }
, configuration
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

pkgs.lib.mapAttrs
  (_: dev: dev.build.deploy)
  evaluated.config.openwrt
