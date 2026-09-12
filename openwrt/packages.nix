{
  pkgs,
  lib,
  config,
  ...
}:

let
  version = builtins.hashString "sha256" (toString config.packages);
  depsApk = config.build.depsPackageApk;
  depsIpk = config.build.depsPackageIpk;
in

{
  options.packages = lib.mkOption {
    type = lib.types.listOf lib.types.str;
    default = [ ];
    description = ''
      Extra packages to install. These are merely names of packages available
      to the package manager through the package source lists configured on the
      device, it is not currently possible to provide packages for installation
      without configuring a package source first.

      For backward compatibility with OpenWrt <= 24.10, opkg will be used if apk
      is unavailable.
    '';
  };

  config = {
    deploySteps.packages = {
      priority = 70;
      copy = ''
        scp ${depsApk} device:/tmp/deps-${version}.apk
        scp ${depsIpk} device:/tmp/deps-${version}.ipk
      '';
      apply = ''
        if command -v apk >/dev/null; then
          sh /tmp/deps-${version}.apk
        elif command -v opkg >/dev/null; then
          if [ "${version}" != "$(opkg info ${depsIpk.package_name} | grep Version | cut -d' ' -f2)" ]; then
            opkg install --autoremove --force-downgrade /tmp/deps-${version}.ipk
          fi
        fi
        rm /tmp/deps-${version}.apk
        rm /tmp/deps-${version}.ipk
      '';
    };

    build.depsPackageApk =
      pkgs.writeTextFile {
        name = "update-world";
        text = ''
          #!/bin/sh
          set -euo pipefail

          if [ ! -f /etc/apk/world.dewclaw ]; then
            echo "Missing world.dewclaw, creating it."
            cp /etc/apk/world /etc/apk/world.dewclaw
          fi

          cp /etc/apk/world.dewclaw /etc/apk/world
          cat <<EOF >> /etc/apk/world
          ${lib.concatStringsSep "\n" config.packages}
          EOF

          apk fix --upgrade
        '';
      };

    build.depsPackageIpk =
      pkgs.runCommand "deps.ipk"
        rec {
          package_name = ".extra-system-deps.";
          control = ''
            Package: ${package_name}
            Version: ${version}
            Architecture: all
            Description: extra system dependencies
            ${lib.optionalString (
              config.packages != [ ]
            ) "Depends: ${lib.concatStringsSep ", " config.packages}"}
          '';
          passAsFile = [ "control" ];
        }
        ''
          mkdir -p deps/control deps/data
          cp $controlPath deps/control/control
          echo 2.0 > deps/debian-binary

          alias tar='command tar --numeric-owner --group=0 --owner=0'
          (cd deps/control && tar -czf ../control.tar.gz ./*)
          (cd deps/data && tar -czf ../data.tar.gz .)
          (cd deps && tar -zcf $out ./debian-binary ./data.tar.gz ./control.tar.gz)
        '';
  };
}
