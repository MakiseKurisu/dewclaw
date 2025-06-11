{ config, lib, ... }:

let
  cfg = config.services.statistics;
in

{
  options.services.statistics = {
    enable = lib.mkEnableOption "statistics service";

    backup = {
      enable = lib.mkEnableOption "statistics periodical backup service" // {
        default = true;
      };

      period = lib.mkOption {
        default = "0 * * * *";
        example = "0 * * * *";
        type = lib.types.str;
        description = ''
          Crontab formatted string for backup period. Protect against unintended
          poweroff event.

          Default to backup every hour.
        '';
      };
    };

    monitors = {
      interfaces = {
        enable = lib.mkEnableOption "network interface monitors" // {
          default = true;
        };

        targets = lib.mkOption {
          default = [ ];
          example = [ "eth0" ];
          type = lib.types.listOf lib.types.str;
          description = ''
            List of network interfaces that will be monitored.
          '';
        };
      };
    };
  };

  config = lib.mkIf cfg.enable {
    packages = [ "luci-app-statistics" ];

    etc = {
      "crontabs/root".text = lib.mkIf cfg.backup.enable ''
        ${cfg.backup.period} service luci_statistics backup
      '';
    };

    uci = {
      settings = {
        collectd.globals.globals = {
          alt_config_file = "/etc/collectd.conf";
        };
        luci_statistics = {
          statistics = {
            collectd = {
              BaseDir = "/var/run/collectd";
              PIDFile = "/var/run/collectd.pid";
              PluginDir = "/usr/lib/collectd";
              TypesDB = "/usr/share/collectd/types.db";
              Interval = 30;
              ReadThreads = 2;
              FQDNLookup = 1;
            };
            rrdtool = {
              default_timespan = "2hour";
              image_width = 600;
              image_height = 150;
              image_path = "/tmp/rrdimg";
            };
            collectd_rrdtool = {
              enable = 1;
              DataDir = "/tmp/rrd";
              RRARows = 288;
              RRASingle = 1;
              backup = 1;
              RRATimespans = "2hour 1day 1week 1month 1year";
            };
            collectd_interface = {
              enable = if cfg.monitors.interfaces.enable == true then 1 else 0;
              Interfaces = cfg.monitors.interfaces.targets;
            };
          };
        };
      };
    };
  };
}
