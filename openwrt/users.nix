{
  config,
  lib,
  pkgs,
  ...
}:

{
  options.users.root = {
    hashedPassword = lib.mkOption {
      type = lib.types.nullOr (lib.types.strMatching "[^\n:]*");
      default = null;
      description = ''
        Hashed password of the user. This should be either a disabled password
        (e.g. `*` or `!`) or use MD5, SHA256, or SHA512.

        You can use `openssl passwd -6 -stdin` to generate this hash.
      '';
    };

    hashedPasswordSecret = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = ''
        Name of the SOPS secret containing the hashed root password.
      '';
    };
  };

  config = {
    assertions = [
      {
        assertion =
          !lib.all (val: val != null) [
            config.users.root.hashedPassword
            config.users.root.hashedPasswordSecret
          ];
        message = "You cannot set both users.root.hashedPassword and users.root.hashedPasswordSecret.";
      }
    ];

    deploySteps.rootPassword =
      lib.mkIf
        (lib.any (val: val != null) [
          config.users.root.hashedPassword
          config.users.root.hashedPasswordSecret
        ])
        {
          priority = 10;
          prepare = ''
            ${
              if config.users.root.hashedPasswordSecret != null then
                ''
                  ${lib.getExe pkgs.jq} -r --arg s ${config.users.root.hashedPasswordSecret} '.[$s]'" | tostring | sub(\"'\"; \"'\\\\'''\")" <"$S" > "$TMP/root_hash"
                ''
              else
                ''
                  # Password hashes contain $ chars, tell shellcheck that this is OK
                  # shellcheck disable=SC2016
                  echo ${lib.escapeShellArg config.users.root.hashedPassword} > "$TMP/root_hash"
                ''
            }
          '';
          copy = ''
            scp "$TMP"/root_hash device:/tmp/
          '';
          apply = ''
            (
              root_hash="$(cat /tmp/root_hash)"

              umask 0077
              touch /tmp/.shadow
              while IFS=: read -r name pw rest; do
                if [ "$name" = root ]; then
                  echo "$name:$root_hash:$rest"
                else
                  echo "$name:$pw:$rest"
                fi
              done </etc/shadow >>/tmp/.shadow
              mv /tmp/.shadow /etc/shadow
            )
          '';
        };
  };
}
