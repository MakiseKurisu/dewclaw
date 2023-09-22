{ config, lib, pkgs, ... }:

let
  cfg = config.openwrt;

  devType = lib.types.submoduleWith {
    specialArgs.pkgs = pkgs;
    modules = [({ name, config, ... }: {
      options = {
        deploy = {
          host = lib.mkOption {
            type = lib.types.str;
            default = name;
          };

          user = lib.mkOption {
            type = lib.types.str;
            default = "root";
            visible = false;
            description = ''
              User name for SSH connections. Doesn't currently to anything useful considering
              that we don't have any kind of `useSudo` option.
            '';
          };

          sshConfig = lib.mkOption {
            type = with lib.types; attrsOf (oneOf [ str int bool path ]);
            default = {};
            description = ''
              SSH options to apply to connections, see {manpage}`ssh_config(5)`.
              Notably these are *not* command-line arguments, although they *will*
              be passed as `-o...` arguments.
            '';
          };

          rebootAllowance = lib.mkOption {
            type = lib.types.ints.unsigned;
            default = 60;
            description = ''
              How long to wait (in seconds) for the device to come back up.
              The timer runs on the deploying host and starts when the device reboots.
            '';
          };

          rollbackTimeout = lib.mkOption {
            type = lib.types.ints.unsigned;
            default = 60;
            description = ''
              How long to wait (in seconds) before rolling back to the old configuration.
              The timer runs on the device and starts once the device has completed its boot cycle.

              ::: {.warning}
              Values under `20` will very likely cause spurious rollbacks.
              :::
            '';
          };
        };

        build = lib.mkOption {
          type = lib.types.attrsOf lib.types.unspecified;
          internal = true;
        };

        deploySteps = lib.mkOption {
          type = lib.types.attrsOf (lib.types.submodule ({ name, ... }: {
            options = {
              name = lib.mkOption { type = lib.types.str; default = name; };
              priority = lib.mkOption { type = lib.types.int; };

              prepare = lib.mkOption { type = lib.types.lines; default = ""; };
              copy = lib.mkOption { type = lib.types.lines; default = ""; };
              apply = lib.mkOption { type = lib.types.lines; };
            };
          }));
          internal = true;
          default = {};
        };
      };

      imports = [
        ./etc.nix
        ./packages.nix
        ./uci.nix
        ./users.nix
      ];

      config = {
        build.deploy =
          let
            steps = lib.sort (a: b: a.priority < b.priority) (lib.attrValues config.deploySteps);
            prepare = lib.concatMapStringsSep "\n\n" (s: "# prepare ${s.name}\n${s.prepare}") steps;
            copy = lib.concatMapStringsSep "\n\n" (s: "# copy ${s.name}\n${s.copy}") steps;
            config_generation = pkgs.runCommand "config_generation.sh" {
                src = ./config_generation.sh;
                deploy_steps = ''
                  ${lib.concatMapStrings
                    (s: ''
                      # apply ${s.name}
                      log "running ${s.name} ..."
                      ${s.apply}
                    '')
                    steps}

                  log 'rebooting device ...'
                '';
                rollback_timeout = config.deploy.rollbackTimeout;
            } ''
              substitute "$src" "$out" \
                --subst-var deploy_steps \
                --subst-var rollback_timeout
              chmod +x "$out"
            '';
            timeout = config.deploy.rollbackTimeout + config.deploy.rebootAllowance;
            sshOpts =
              ''-o ControlPath="$TMP/cm" ''
              + lib.escapeShellArgs
                (lib.mapAttrsToList
                  (arg: val: "-o${arg}=${
                    if val == true then "yes"
                    else if val == false then "no"
                    else toString val
                  }")
                  ({
                    ControlMaster = "auto";
                    User = config.deploy.user;
                    Hostname = config.deploy.host;
                  } // config.deploy.sshConfig)
                );
          in
            pkgs.writeShellScriptBin "deploy-${name}" ''
              set -euo pipefail
              shopt -s inherit_errexit

              BOLD='\e[1m'
              PURP='\e[35m'
              CYAN='\e[36m'
              RED='\e[31m'
              NORMAL='\e[0m'

              log() {
                printf "$BOLD$PURP> %s$NORMAL\n" "$*"
              }
              log_err() {
                printf "$BOLD$RED> %s$NORMAL\n" "$*"
              }

              # generate a (reasonably) unique logger tag. mustn't be too long,
              # or it'll be truncated and matching will fail.
              TAG="apply_config_$$_$RANDOM"

              ssh() {
                command ssh ${sshOpts} device "$@"
              }

              scp() {
                command scp -Op ${sshOpts} "$@"
              }

              main() {
                export TMP="$(umask 0077; mktemp -d)"

                trap '
                  [ -e "$TMP/cm" ] && ssh -O exit 2>/dev/null || true
                  rm -rf "$TMP"
                ' EXIT

                log 'preparing files'
                ${prepare}

                log 'copying files'
                scp ${config_generation} device:/etc/init.d/config_generation
                ${copy}

                # apply the new config and wait for the box to go down via ssh connection
                # timeout.
                log 'applying config'
                ssh '
                  export LOG_FMT="'"$CYAN"'>> %s'"$NORMAL"'"
                  /etc/init.d/config_generation apply </dev/null 2>&1 \
                    | logger -t '"$TAG" &
                ssh 'logread -l9999 -f' | awk -v FS="$TAG: " '$2 { print $2 }' || true

                log 'waiting for device to return'
                __DO_WAIT=1 timeout --foreground ${toString timeout}s "$0" || {
                  log_err 'configuration change failed, device will roll back and reboot'
                  exit 1
                }

                log 'new configuration applied'
              }

              _wait() {
                while ! ssh -oConnectTimeout=5 '/etc/init.d/config_generation commit'; do
                  sleep 1
                done
              }

              case "''${__DO_WAIT:-}" in
                "") main ;;
                *) _wait ;;
              esac
            '';
      };
    })];
  };

in

{
  options.openwrt = lib.mkOption {
    type = lib.types.attrsOf devType;
    default = {};
  };
}
