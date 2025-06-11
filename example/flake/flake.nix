{
  description = "dewclaw flake example";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-parts.url = "github:hercules-ci/flake-parts";
    dewclaw.url = "github:MakiseKurisu/dewclaw";
  };

  outputs =
    inputs@{ self
    , nixpkgs
    , flake-parts
    , dewclaw
    , ...
    }: flake-parts.lib.mkFlake { inherit inputs; } {
      systems = [ "x86_64-linux" ];
      perSystem = { config, self', inputs', pkgs, system, ... }: {
        formatter = pkgs.nixfmt-rfc-style;
        packages = {
          dewclaw-env = pkgs.callPackage dewclaw {
            configuration = import ../classic/example.nix;
          };
          default = self.packages.x86_64-linux.dewclaw-env;
        };
      };
    };
}
