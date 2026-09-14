{
  pkgs,
  lib,
  config,
  ...
}:

let
  cfg = config.etc;

  secretHash = builtins.hashString "sha256";
in

{
  options.etc = lib.mkOption {
    type = lib.types.attrsOf (
      lib.types.submoduleWith {
        description = "`/etc` file description";
        modules = [
          (
            { name, ... }:
            {
              options = {
                enable = lib.mkEnableOption "this `/etc` file" // {
                  default = true;
                };

                text = lib.mkOption {
                  type = lib.types.nullOr lib.types.lines;
                  default = null;
                  description = ''
                    Contents of the file.
                  '';
                };

                secret = lib.mkOption {
                  type = lib.types.nullOr lib.types.str;
                  default = null;
                  description = ''
                    Name of the SOPS secrets containing the contents of
                    the file.
                  '';
                };
              };
            }
          )
        ];
      }
    );
    default = { };
    description = ''
      Extra files to *create* in the target `/etc`. It is not currently possible to
      *delete* files from the target.

      This option should usually not be used if there's a UCI way to achieve the
      same effect.
    '';
  };

  config = lib.mkIf (cfg != { }) {
    assertions = lib.mapAttrsToList (name: file: {
      assertion = lib.xor (isNull file.text) (isNull file.secret);
      message = "Either text or secret has to be defined for etc.\"${name}\", but not both.";
    }) cfg;

    deploySteps.etc = {
      priority = 20;
      prepare = lib.concatStrings (
        lib.mapAttrsToList (
          _: file:
          lib.optionalString (file.enable && !isNull file.secret) ''
            ${lib.getExe pkgs.jq} -r --arg s ${file.secret} '.[$s]' <"$S" > "$TMP/${secretHash file.secret}"
          ''
        ) cfg
      );
      copy = lib.concatStrings (
        lib.mapAttrsToList (
          _: file:
          lib.optionalString (file.enable && !isNull file.secret) ''
            scp "$TMP"/${secretHash file.secret} device:/tmp/
          ''
        ) cfg
      );
      apply = lib.concatStrings (
        lib.mapAttrsToList (
          name: file:
          lib.optionalString (file.enable) ''
            ${lib.optionalString (dirOf name != ".") ''
              mkdir -p ${lib.escapeShellArg (dirOf "/etc/${name}")}
            ''}
            ${lib.optionalString (!isNull file.text) ''
              echo ${lib.escapeShellArg file.text} >${lib.escapeShellArg "/etc/${name}"}
            ''}
            ${lib.optionalString (!isNull file.secret) ''
              mv /tmp/${secretHash file.secret} ${lib.escapeShellArg "/etc/${name}"}
            ''}
          ''
        ) cfg
      );
    };
  };
}
