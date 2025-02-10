{ config, lib, pkgs, ... }:

let
  cfg = config.openwrt;

  devType = lib.types.submoduleWith {
    specialArgs.pkgs = pkgs;
    description = "OpenWrt configuration";
    modules = [
      ({ name, config, ... }: {
        options = {
          deploy = {
            host = lib.mkOption {
              type = lib.types.str;
              default = name;
              example = "192.168.0.1";
              description = ''
                Host to deploy to. Defaults to the attribute name, but this may have unintended
                side-effects when deploying to the DNS server of the current network. Prefer
                IP addresses or names of `ssh_config` host blocks for such cases.
              '';
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
              default = { };
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

                ::: {.note}
                During reload-only deployment this timeout *includes* the time needed to apply
                configuration, which may be substatial if network activity is necessary (eg when
                installing packages).
                :::
              '';
            };

            reloadServiceWait = lib.mkOption {
              type = lib.types.ints.unsigned;
              default = 10;
              description = ''
                How long to wait (in seconds) during reload-only deployment to allow for more
                graceful service restarts. Small values make reloads faster, but since OpenWrt
                has no mechanism to figure out *when* all services are done starting this also
                introduces possible failure points.
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
                name = lib.mkOption {
                  type = lib.types.str;
                  default = name;
                  internal = true;
                };
                priority = lib.mkOption {
                  type = lib.types.int;
                  internal = true;
                };

                prepare = lib.mkOption {
                  type = lib.types.lines;
                  default = "";
                  internal = true;
                };
                copy = lib.mkOption {
                  type = lib.types.lines;
                  default = "";
                  internal = true;
                };
                apply = lib.mkOption {
                  type = lib.types.lines;
                  internal = true;
                };
              };
            }));
            internal = true;
            default = { };
          };
        };

        imports = [
          ./etc.nix
          ./packages.nix
          ./uci.nix
          ./users.nix
          ./providers.nix
          ./services
        ];

        config = {
          build.deploy =
            let
              steps = lib.sort (a: b: a.priority < b.priority) (lib.attrValues config.deploySteps);
              prepare = lib.concatMapStringsSep "\n\n" (s: "# prepare ${s.name}\n${s.prepare}") steps;
              copy = lib.concatMapStringsSep "\n\n" (s: "# copy ${s.name}\n${s.copy}") steps;
              config_generation = pkgs.runCommand "config_generation.sh"
                {
                  src = ./config_generation.sh;
                  deploy_steps = ''
                    ${lib.concatMapStrings
                      (s: ''
                        # apply ${s.name}
                        log "running ${s.name} ..."
                        ${s.apply}
                      '')
                      steps}
                  '';
                  rollback_timeout = config.deploy.rollbackTimeout;
                  reload_service_wait = config.deploy.reloadServiceWait;
                } ''
                substitute "$src" "$out" \
                  --subst-var deploy_steps \
                  --subst-var rollback_timeout \
                  --subst-var reload_service_wait
                chmod +x "$out"
              '';
              rebootTimeout = config.deploy.rollbackTimeout + config.deploy.rebootAllowance;
              reloadTimeout = config.deploy.rollbackTimeout + config.deploy.reloadServiceWait;
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
                command ssh -n ${sshOpts} device "$@"
              }

              scp() {
                command scp -Op ${sshOpts} "$@"
              }

              usage() {
                echo "usage: $(basename "$0") [options]"
                echo
                echo "options:"
                echo "  --help        Show this help"
                echo "  --reload      Reload/deploy config without rebooting"
              }

              main() {
                RELOAD_ONLY=false
                TIMEOUT=${toString rebootTimeout}s

                for arg in "$@"; do
                  case "$arg" in
                    --help)
                      usage
                      exit 0
                      ;;
                    --reload)
                      RELOAD_ONLY=true
                      TIMEOUT=${toString reloadTimeout}s
                      ;;
                    *)
                      echo "error: unknown argument: $arg" >&2
                      echo >&2
                      usage >&2
                      exit 1
                      ;;
                  esac
                done

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
                ssh -Nf
                if $RELOAD_ONLY; then
                  ssh 'logread -l9999 -f' &
                  ssh '/etc/init.d/config_generation prepare_reload'
                  ssh '/etc/init.d/config_generation start' &
                  ssh '/etc/init.d/config_generation apply_reload 2>&1 | logger -t '"$TAG"
                  ssh -O exit
                else
                  ssh 'logread -l9999 -f' &
                  ssh '/etc/init.d/config_generation apply_reboot 2>&1 | logger -t '"$TAG"
                  # if the previous command succeeded we're up for a reboot, at which
                  # point ssh will exit with a 255 status
                  wait %1 || true
                fi \
                  | awk -v FS="$TAG: " '
                      $2 { print $2 }
                    '

                log 'waiting for device to return'
                __DO_WAIT=1 timeout --foreground $TIMEOUT "$0" || {
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
                "") main "$@" ;;
                *) _wait ;;
              esac
            '';
        };
      })
    ];
  };

in

{
  options.openwrt = lib.mkOption {
    type = lib.types.attrsOf devType;
    default = { };
    description = ''
      OpenWrt device configurations. Each attribute will produce an indepdent deployment
      script that applies the corresponding configuration to the target device.
    '';
  };
}
