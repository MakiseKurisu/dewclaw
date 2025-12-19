{
  pkgs,
  lib,
  config,
  ...
}:

let
  package_name = "dewclaw-deps";
  # apk rejects hash as version number, due to the letters. Convert them to
  # digits.
  version = let
    hash = builtins.hashString "sha256" (toString config.packages);
    digitsOnly =
      lib.stringAsChars
        (x:
          if x == "a" then "10"
          else if x == "b" then "11"
          else if x == "c" then "12"
          else if x == "d" then "13"
          else if x == "e" then "14"
          else if x == "f" then "15"
          else x
        )
        hash;
    in
      digitsOnly;
  depsApk = config.build.depsPackageApk;
  depsIpk = config.build.depsPackageIpk;
in

{
  options.packages = lib.mkOption {
    type = lib.types.listOf lib.types.str;
    default = [ ];
    description = ''
      Extra packages to install. These are merely names of packages available
      for package manager through the package source lists configured on the
      device, it is not currently possible to provide packages for installation
      without configuring a package source first.

      For backward compatibility with OpenWRT <= 24.10, opkg will be used if apk
      is unavailable.
    '';
  };

  config = {
    assertions = [
      {
        assertion = lib.versionAtLeast pkgs.apk-tools.version "3.0.0";
        message = "apk-tools >= 3.0.0 is required to build APK packages (found ${pkgs.apk-tools.version}).";
      }
    ];

    deploySteps.packages = {
      priority = 80;
      copy = ''
        scp ${depsApk} device:/tmp/deps-${version}.apk
        scp ${depsIpk} device:/tmp/deps-${version}.ipk
      '';
      apply = ''
        if command -v apk >/dev/null; then
          if [ "${version}" != "$(apk list --installed --manifest "${package_name}" | cut -d' ' -f2)" ]; then
            apk update
            # TODO: sign packages?
            # TODO: remove old packages that were previously pulled in as dependencies, but no longer needed.
            apk add --allow-untrusted /tmp/deps-${version}.apk
          fi
        elif command -v opkg >/dev/null; then
          if [ "${version}" != "$(opkg info ${package_name} | grep Version | cut -d' ' -f2)" ]; then
            opkg update
            opkg install --autoremove --force-downgrade /tmp/deps-${version}.ipk
          fi
        else
          echo "error: missing package manager (tried 'apk' and 'opkg')"
          return 1
        fi
        rm /tmp/deps-${version}.apk
        rm /tmp/deps-${version}.ipk
      '';
    };

    build.depsPackageApk =
      pkgs.runCommand "deps.apk"
        {
          nativeBuildInputs = [
            pkgs.apk-tools
          ];
        }
        ''
          apk mkpkg \
            --info="name:${package_name}" \
            --info="version:${version}" \
            --info="arch:noarch" \
            ${lib.concatMapStringsSep " " (x: "--info=depends:${x}") config.packages} \
            --output "$out"
        '';

    build.depsPackageIpk =
      pkgs.runCommand "deps.ipk"
        {
          control = ''
            Package: ${package_name}
            Version: ${version}
            Provides: .extra-system-deps.
            Replaces: .extra-system-deps.
            Conflicts: .extra-system-deps.
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
