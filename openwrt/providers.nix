{ config, lib, ... }:

let
  cfg = config.providers;
in

{
  options.providers = lib.mkOption {
    type = lib.types.attrsOf lib.types.str;
    default = { };
    description = ''
      Alternative method to replace critical packages with another variant, for
      example `dnsmasq`.

      This option should only be used when absolutely necessary, as packages
      installed this way cannot be automatically cleaned up like `packages`.
    '';
    example = ''
      {
        dnsmasq = "dnsmasq-full";
      }
    '';
  };

  config = lib.mkIf (cfg != { }) {
    deploySteps.providers = {
      priority = 70;
      apply = lib.concatStrings (
        [
          ''
            opkg update
          ''
        ]
        ++ (lib.mapAttrsToList (name: value: ''
          (
            pkg="${name}"
            provider="${value}"
            if ! opkg status "$provider" 2>/dev/null | grep -e Status: | grep -q installed; then
              temp="$(mktemp -d)"
              cd "$temp"
              opkg download "$pkg" "$provider"
              cd "$OLDPWD"
              opkg install "$provider" --cache . || true
              opkg remove "$pkg"
              opkg install "$provider" --cache . || opkg install "$pkg" --cache .
              rm -rf "$temp"
              if [ "$provider" = "dnsmasq-full" ]; then
                # workaround dnsmasq-full bug when running in lxc
                # https://forum.openwrt.org/t/multiple-dhcp-dns-server-instances-not-work/130849/11
                sed -i "s|procd_add_jail_mount /etc/passwd|procd_add_jail_mount /dev/urandom /etc/passwd|" /etc/init.d/dnsmasq
                /etc/init.d/dnsmasq start
              fi
            fi
          )
        '') cfg)
      );
    };
  };
}
