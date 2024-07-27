{ config, lib, ... }:

let
  cfg = config.etc;
in

{
  options.etc = lib.mkOption {
    type = lib.types.attrsOf (lib.types.submoduleWith {
      description = "`/etc` file description";
      modules = [
        ({ name, ... }: {
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
        })
      ];
    });
    default = { };
    description = ''
      Extra files to *create* in the target `/etc`. It is not currently possible to
      *delete* files from the target.

      This option should usually not be used if there's a UCI way to achieve the
      same effect.
    '';
  };

  config = lib.mkIf (cfg != { }) {
    deploySteps.etc = {
      priority = 20;
      apply =
        lib.concatStrings
          (lib.mapAttrsToList
            (name: file: lib.optionalString (file.enable) ''
              ${lib.optionalString (dirOf name != ".") ''
                mkdir -p ${lib.escapeShellArg (dirOf "/etc/${name}")}
              ''}
              echo ${lib.escapeShellArg file.text} >${lib.escapeShellArg "/etc/${name}"}
            '')
            cfg);
    };
  };
}
