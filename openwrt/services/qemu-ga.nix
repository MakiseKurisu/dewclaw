{ config, lib, ... }:

let
  cfg = config.services.qemu-ga;
in

{
  options.services.qemu-ga = {
    enable = lib.mkEnableOption "QEMU guest agent";

    package = lib.mkOption {
      default = "qemu-ga";
      example = "qemu-ga";
      type = lib.types.str;
      description = ''
        QEMU guest agent package to use.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    packages = [
      cfg.package
    ];
  };
}
