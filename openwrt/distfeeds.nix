{ ... }:
{
  config = {
    deploySteps.distfeeds = {
      priority = 30;
      apply = ''
        if command -v apk >/dev/null; then
          apk update
        elif command -v opkg >/dev/null; then
          opkg update
        else
          echo "error: missing package manager (tried 'apk' and 'opkg')"
          return 1
        fi
      '';
    };
  };
}
