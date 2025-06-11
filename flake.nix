{
  description = "dewclaw: semi-declarative OpenWrt configuration ";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    flake-parts.url = "github:hercules-ci/flake-parts";
  };

  outputs =
    inputs@{
      self,
      nixpkgs,
      flake-parts,
      ...
    }:
    flake-parts.lib.mkFlake { inherit inputs; } {
      systems = [ "x86_64-linux" ];
      perSystem =
        {
          config,
          self',
          inputs',
          pkgs,
          system,
          ...
        }:
        {
          formatter = pkgs.nixfmt-rfc-style;
          packages = {
            dewclaw-env = pkgs.callPackage ./default.nix {
              configuration = import ./example/classic/example.nix;
            };
            dewclaw-book = pkgs.callPackage ./doc { };
            default = self.packages.x86_64-linux.dewclaw-env;
          };

          devShells.default = pkgs.mkShell {
            packages = [
              pkgs.nixfmt-rfc-style
              pkgs.shfmt
              pkgs.treefmt
            ];
          };
        };
    };
}
