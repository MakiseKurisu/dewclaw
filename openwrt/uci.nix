{
  pkgs,
  lib,
  config,
  ...
}:

let
  cfg = config.uci;

  formatConfig =
    nix:
    lib.concatStringsSep "\n" (
      lib.flatten (
        lib.mapAttrsToList (config: sections: [
          "package ${config}"
          (lib.mapAttrsToList formatSections sections)
        ]) nix
      )
    );

  formatSections =
    type: sections:
    if lib.isAttrs sections then
      lib.mapAttrsToList (name: vals: [
        "config ${type} ${formatScalar name}"
        (formatSection vals)
      ]) sections
    else
      map (vals: [
        "config ${type}"
        (formatSection vals)
      ]) sections;

  formatSection = lib.mapAttrsToList (
    option: value:
    if lib.isList value then
      map (value: "  list ${option} ${formatScalar value}") value
    else
      "  option ${option} ${formatScalar value}"
  );

  formatScalar =
    val:
    if lib.isBool val then
      (if val then "'1'" else "'0'")
    else if lib.isInt val then
      "'${toString val}'"
    else if lib.isAttrs val then
      "'${secretName val._secret}'"
    else
      "'${lib.replaceStrings [ "'" ] [ "'\\''" ] val}'";

  secretName = sec: "@secret_${sec}_${builtins.hashString "sha256" sec}@";

  collectSecrets =
    nix:
    lib.pipe nix [
      lib.attrValues
      (lib.concatMap lib.attrValues)
      (lib.concatMap (s: if lib.isAttrs s then lib.attrValues s else s))
      (lib.concatMap lib.attrValues)
      (lib.concatMap lib.toList)
      (lib.concatMap (
        v:
        if v ? _secret then
          [
            {
              name = v._secret;
              value = { };
            }
          ]
        else
          [ ]
      ))
      lib.listToAttrs
      lib.attrNames
    ];

  uciIdentifierCheck =
    type: attrs:
    let
      invalid = lib.filter (
        n: builtins.match (if type == "config" then "[a-zA-Z0-9_-]+" else "[a-zA-Z0-9_]+") n == null
      ) (lib.attrNames attrs);
    in
    lib.warnIf (invalid != [ ]) ("Invalid UCI ${type} names found: ${toString invalid}") (
      invalid == [ ]
    );
in

{
  options.uci = {
    secretsCommand = lib.mkOption {
      type = lib.types.path;
      default = pkgs.writeScript "no-secrets" "echo '{}'";
      description = ''
        Command to retrieve secrets. Must be an executable command that
        returns a JSON object on `stdout`, with secret names as keys and string
        values.
      '';
    };

    sopsSecrets = lib.mkOption {
      type = lib.types.nullOr lib.types.path;
      default = null;
      description = ''
        sops secrets file. This as a shorthand for setting {option}`secretsCommand`
        to a script that calls `sops -d <path>`. Path semantics apply: if the given
        path is a path literal it is copied into the store and the resulting absolute
        path is used, otherwise the given path is used verbatim in the generated script.
      '';
    };

    settings = lib.mkOption {
      type =
        with lib.types;
        let
          scalar = oneOf [
            str
            int
            bool
            (submodule {
              options._secret = lib.mkOption {
                type = str;
                description = ''
                  Name of the secret to insert into the config from data exported
                  by {option}`secretsCommand`. Secrets are always interpolated as
                  strings, which uci allows for scalars. Lists cannot currently
                  be made entirely secret, only individual values of lists can.
                '';
              };
            })
          ];
          uciAttrsOf = type: elem: addCheck (attrsOf elem) (uciIdentifierCheck type);
          options = uciAttrsOf "option" (either scalar (listOf scalar));
        in
        submodule {
          freeformType =
            # <config>.<name>=type       -> config.type.name ...
            # <config>.@<anonymous>=type -> config.type = [{ ... }]
            # config
            attrsOf (
              # type
              attrsOf (
                either (uciAttrsOf "section" options) # name ...
                  (listOf options) # [{ ... }]
              )
            )
            // {
              description = "UCI config";
            };
        };
      default = { };
      description = ''
        UCI settings in hierarchical representation. The toplevel key of this
        set denotes a UCI package, the second level the type of section, and the
        third level may be either a list of anonymous setions or a set of named
        sections.

        Packages defined here will replace existing settings on the system entirely,
        no merging with existing configuration is done.
      '';
      example = {
        network = {
          interface.loopback = {
            device = "lo";
            proto = "static";
            ipaddr = "127.0.0.1";
            netmask = "255.0.0.0";
          };

          globals = [ { ula_prefix = "fdb8:155d:7ef5::/48"; } ];
        };
      };
    };

    retain = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      example = [ "ucitrack" ];
      description = ''
        UCI package configuration to retain. Packages listed here will not have preexisting
        configuration deleted during deployment, even if no matching {option}`settings`
        are defined.
      '';
    };
  };

  config = {
    uci.secretsCommand = lib.mkIf (cfg.sopsSecrets != null) (
      pkgs.writeShellScript "sops" ''
        ${pkgs.sops}/bin/sops --output-type json -d ${lib.escapeShellArg "${cfg.sopsSecrets}"}
      ''
    );

    build.configFile = pkgs.writeText "config" (formatConfig cfg.settings);

    deploySteps.uciConfig =
      # correctness of config identifiers can't be checked on the type level
      # because submodules are weird sometimes, so we have to do it here.
      assert uciIdentifierCheck "config" cfg.settings;
      let
        cfgName = baseNameOf config.build.configFile;
        jq = "${pkgs.jq}/bin/jq";
        configured = lib.attrNames config.uci.settings ++ config.uci.retain;
      in
      {
        priority = 90;
        prepare = ''
          cp --no-preserve=all ${config.build.configFile} "$TMP"
          (
            umask 0077
            C="$TMP"/${cfgName}
            S="$TMP"/secrets
            ${cfg.secretsCommand} > "$S"
            [ "$(${jq} -r type <"$S")" == "object" ] || {
              log_err "secrets command did not produce an object"
              exit 1
            }
            ${lib.concatMapStrings (
              secret:
              let
                arg = lib.escapeShellArg secret;
              in
              ''
                has="$(${jq} -r --arg s ${arg} 'has($s)' <"$S")"
                $has || {
                  log_err secret ${arg} not defined
                  exit 1
                }
                ${pkgs.replace-secret}/bin/replace-secret \
                  ${lib.escapeShellArg (secretName secret)} \
                  <(${jq} -r --arg s ${arg} '.[$s]'" | tostring | sub(\"'\"; \"'\\\\'''\")" <"$S") \
                  "$C"
              ''
            ) (collectSecrets cfg.settings)}
          )
        '';
        copy = ''
          scp "$TMP"/${cfgName} device:/tmp/
        '';
        apply = ''
          uci import < /tmp/${cfgName}
          uci commit

          (
            cd /etc/config
            for cfg in *; do
              case "$cfg" in
                ${lib.optionalString (configured != [ ]) ''
                  ${lib.concatMapStringsSep "|" lib.escapeShellArg configured}) : ;;
                ''}
                *) rm "$cfg" ;;
              esac
            done
          )
        '';
      };
  };
}
