{ config, lib, ... }:

let
  cfg = config.services.qemu-ga;
in

{
  options.services.qemu-ga = {
    enable = lib.mkEnableOption (lib.mdDoc "Enable qemu-ga service.");

    package = lib.mkOption {
      default = "qemu-ga";
      example = "qemu-ga";
      type = lib.types.str;
      description = ''
        qemu-ga package to use.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    packages = [
      cfg.package
    ];
  };
}
