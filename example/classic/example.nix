# example config for a qemu image of openwrt that is accessible
# via port 2222 on localhost. the root password is set to `a`
# and a few utilities are installed, otherwise the configuration
# is a subset of the default config.
#
# to use this example run a squashfs image of openwrt
# (eg https://downloads.openwrt.org/releases/22.03.5/targets/x86/64/openwrt-22.03.5-x86-64-generic-squashfs-combined.img.gz)
# with something like
#
#   qemu-system-x86_64 -M q35,accel=kvm \
#     -drive file=openwrt-22.03.5-x86-64-generic-squashfs-combined.img,id=d0,if=none,bus=0,unit=0 \
#     -device ide-hd,drive=d0,bus=ide.0 \
#     -nic user,hostfwd=tcp::2222-:22,hostfwd=tcp::8080-:80
#
# and run `uci set network.lan.proto=dhcp; uci commit; reload_config`
# from the serial console.
#
# age keys for sops are as follow:
#
# SOPS_AGE_KEY=AGE-SECRET-KEY-1292U9T04N6MJUK223038MD246X4G2K8GPDWHVHY09JVCLSRUS6TQ6988D9

{
  openwrt.example = {
    deploy.host = "localhost";
    deploy.sshConfig = {
      Port = 2222;
      NoHostAuthenticationForLocalhost = true;
      IdentityFile = ./example.key;
    };

    packages = [ "losetup" "mount-utils" "coreutils-stat" "htop" ];
    providers = {
      dnsmasq = "dnsmasq-full";
    };
    users.root.hashedPassword = "$6$n/dIMAV5QZyMp6UQ$fSvzsPZ8Vl1kzq9Mm3oQy81hxDkPqv04YPSlBOpqjMQKGu6xjcIuXrrfvf3Dcm8ea46oG8XtEPm6AViOFESF81";
    etc."dropbear/authorized_keys".text = ''
      ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIHGQEKlJPpUkR+NQHObd1CWWM7ItbkFLk80PyK+b+2EN example@key
    '';

    services = {
      qemu-ga.enable = true;
    };

    uci.sopsSecrets = ./secrets.yaml;
    # leave the ucitrack and firewall packages as they are, retaining defaults if
    # freshly installed. the firewall rules are verbose and ucitrack is mostly not
    # necessary, so we don't want to include either here. we also keep luci to not
    # break the web interface, although configuration through the web ui is discouraged.
    # rpcd is needed for luci.
    uci.retain = [ "ucitrack" "firewall" "luci" "rpcd" ];
    uci.settings = {
      dropbear.dropbear = [{
        PasswordAuth = "on";
        RootPasswordAuth = "on";
        Port = 22;
      }];

      network = {
        device = [{
          name = "br-lan";
          ports = "eth0";
          type = "bridge";
        }];

        globals = [{
          ula_prefix = "fd10:155d:7ef5::/48";
        }];

        interface.lan = {
          device = "br-lan";
          proto = "dhcp";
        };

        interface.loopback = {
          device = "lo";
          ipaddr = "127.0.0.1";
          netmask = "255.0.0.0";
          proto = "static";
        };
      };

      uhttpd.uhttpd.main = {
        listen_http = [ "0.0.0.0:80" "[::]:80" ];
        lua_prefix = [ "/cgi-bin/luci=/usr/lib/lua/luci/sgi/uhttpd.lua" ];
        home = "/www";
        cgi_prefix = "/cgi-bin";
        ubus_prefix = "/ubus";
      };

      system = {
        system = [{
          hostname = "OpenWrt";
          timezone = "UTC";
          ttylogin = 0;
          log_size = 64;
          urandom_seed = 0;
          notes._secret = "notes";
        }];

        timeserver.ntp = {
          enabled = true;
          enable_server = false;
          server = [
            "0.openwrt.pool.ntp.org"
            "1.openwrt.pool.ntp.org"
            "2.openwrt.pool.ntp.org"
            "3.openwrt.pool.ntp.org"
          ];
        };
      };
    };
  };
}
