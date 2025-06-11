{
  config,
  lib,
  pkgs,
  ...
}:
{
  options = {
    secretsCommand = lib.mkOption {
      type = lib.types.path;
      default = pkgs.writeScript "no-secrets" "echo '{}'";
      description = ''
        Command to retrieve secrets. Must be an executable command that
        returns a JSON object on `stdout`, with secret names as keys and string
        values.
      '';
    };

    sopsSecrets = lib.mkOption {
      type = lib.types.nullOr lib.types.path;
      default = null;
      description = ''
        sops secrets file. This as a shorthand for setting {option}`secretsCommand`
        to a script that calls `sops -d <path>`. Path semantics apply: if the given
        path is a path literal it is copied into the store and the resulting absolute
        path is used, otherwise the given path is used verbatim in the generated script.
      '';
    };
  };

  config = {
    secretsCommand = lib.mkIf (config.sopsSecrets != null) (
      lib.getExe (
        pkgs.writeShellApplication {
          name = "sops";
          text = ''
            ${lib.getExe pkgs.sops} --output-type json -d ${lib.escapeShellArg "${config.sopsSecrets}"}
          '';
        }
      )
    );

    deploySteps.extractSecrets = {
      priority = 5;
      prepare = ''
        S="$TMP"/secrets
        (
          umask 0077
          ${config.secretsCommand} > "$S"
          [ "$(${lib.getExe pkgs.jq} -r type <"$S")" == "object" ] || {
            log_err "secrets command did not produce an object"
            exit 1
          }
        )
      '';
      apply = "";
    };
  };
}
