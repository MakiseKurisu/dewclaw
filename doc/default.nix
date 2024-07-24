{ pkgs ? import <nixpkgs> { config = { }; overlays = [ ]; }
}:

let
  evaluated = pkgs.lib.evalModules {
    modules = [
      ../openwrt
    ];
    specialArgs = {
      inherit pkgs;
    };
  };

  optionsDoc = pkgs.nixosOptionsDoc {
    inherit (evaluated) options;
    transformOptions = opt:
      let
        cwd = toString ../.;
        shorten = decl:
          let
            removed = pkgs.lib.removePrefix cwd decl;
          in
          if removed != decl
          then {
            url =
              "https://github.com/MakiseKurisu/dewclaw/blob/main${removed}"
              + (if pkgs.lib.hasSuffix ".nix" removed
              then ""
              else "/default.nix");
            name = "<dewclaw${removed}>";
          }
          else removed;
      in
      opt // { declarations = map shorten opt.declarations; };
  };
in

pkgs.runCommand "dewclaw-book"
{
  src = ./src;
  buildInputs = [ pkgs.mdbook ];
} ''
  cp -r --no-preserve=all $src ./src
  ln -s ${optionsDoc.optionsCommonMark} ./src/options.md
  ln -s ${../README.md} ./src/README.md
  mdbook build
  mv book $out
''
