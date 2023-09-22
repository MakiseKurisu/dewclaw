{ config, lib, ... }:

let
  cfg = config.etc;
in

{
  options.etc = lib.mkOption {
    type = lib.types.attrsOf (lib.types.submodule ({ name, ... }: {
      options = {
        enable = lib.mkEnableOption "this `/etc` file" // {
          default = true;
        };

        text = lib.mkOption {
          type = lib.types.lines;
          description = ''
            Contents of the file.
          '';
        };
      };
    }));
    default = {};
  };

  config = lib.mkIf (cfg != {}) {
    deploySteps.etc = {
      priority = 8000;
      apply =
        lib.concatStrings
          (lib.mapAttrsToList
            (name: file: lib.optionalString (file.enable) ''
              ${lib.optionalString (dirOf name != ".") ''
                mkdir -p ${lib.escapeShellArg (dirOf name)}
              ''}
              echo ${lib.escapeShellArg file.text} >${lib.escapeShellArg "/etc/${name}"}
            '')
            cfg);
    };
  };
}
