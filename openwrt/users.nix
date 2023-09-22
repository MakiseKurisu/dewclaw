{ config, lib, ... }:

{
  options.users.root.hashedPassword = lib.mkOption {
    type = lib.types.nullOr (lib.types.strMatching "[^\n:]*");
    default = null;
    description = ''
      Hashed password of the user. This should be either a disabled password
      (e.g. `*` or `!`) or use MD5, SHA256, or SHA512.
    '';
  };

  config = {
    deploySteps.rootPassword = lib.mkIf (config.users.root.hashedPassword != null) {
      priority = 5000;
      apply = ''
        (
          umask 0077
          touch /tmp/.shadow
          while IFS=: read name pw rest; do
            if [ "$name" = root ]; then
              echo "$name:"${lib.escapeShellArg config.users.root.hashedPassword}":$rest"
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
