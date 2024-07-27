{ pkgs, lib, config, ... }:

let
  deps = config.build.depsPackage;
in

{
  options.packages = lib.mkOption {
    type = lib.types.listOf lib.types.str;
    default = [ ];
    description = ''
      Extra packages to install. These are merely names of packages available
      to opkg through the package source lists configured on the device, it is
      not currently possible to provide packages for installation without
      configuring an opkg source first.
    '';
  };

  config = {
    deploySteps.packages = {
      priority = 80;
      copy = ''
        scp ${deps} device:/tmp/deps-${deps.version}.ipk
      '';
      apply = ''
        if [ ${deps.version} != "$(opkg info ${deps.package_name} | grep Version | cut -d' ' -f2)" ]; then
          opkg update
          opkg install --autoremove --force-downgrade /tmp/deps-${deps.version}.ipk
        fi
      '';
    };

    build.depsPackage = pkgs.runCommand "deps.ipk"
      rec {
        package_name = ".extra-system-deps.";
        version = builtins.hashString "sha256" (toString config.packages);
        control = ''
          Package: ${package_name}
          Version: ${version}
          Architecture: all
          Description: extra system dependencies
          ${lib.optionalString
            (config.packages != [])
            "Depends: ${lib.concatStringsSep ", " config.packages}"
          }
        '';
        passAsFile = [ "control" ];
      } ''
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
