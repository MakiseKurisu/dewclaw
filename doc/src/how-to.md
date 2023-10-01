# How to use

dewclaw can declaratively manage some (but by far not all) aspects of OpenWRT devices.
Packages can be installed (and subsequently removed) declaratively by listing them in the `packages` option.
UCI configs can be set declaratively using the `uci.settings` hierarchy, or be marked for imperative configuration by adding the appropriate package names to `uci.retain`.
Files in `/etc` can be create with the `etc` hierarchy.

## Mapping UCI options

Mapping existing UCI configurations to `uci.settings` values is straight-forward starting with the output of `uci show`. UCI outputs its configuration in a specific format:
```
package.namedSection=type1
package.namedSection.option='value'
package.namedSection.list='value1' 'value2' ...
package.@anonSection=type2
package.@anonSection.option='value'
```

In dewclaw `package` is the top level of keys in `uci.settings`, `type` is the second level, and below the `type` level we either have a third `namedSection` level or a list of `anonSection`s.
Each named or anonymous section is itself a set of `option = value` assignments.
dewclaw cannot mix named and anonymous sections, any given type must be configured entirely with named sections or entirely with unnamed sections.

The example `uci show` output above would thus map to the following dewclaw device configuration:
```nix
openwrt.router.uci.settings = {
  package.type1 = {
    namedSection = {
      option = "value";
      list = [ "value1" "value2" ];
    };
  };

  package.type2 = [
    {
      option = "value";
    }
  ];
}
```

Option values may be any UCI-compatible type: strings, paths and integers are passed through, booleans are converted to `0/1`.
Additionally there is support for secret values, with a [sops] secrets backend built into dewclaw directly.
Secrets are loaded from a backend during deployment time and will be interpolated into the generated UCI config.
To load an option value from a secret, set `option._secret = "secretName"` in `uci.settings`.

## Building a configuration

Once a configuration for any number of devices is written it can be passed to dewclaw and built into a set of deployment scripts:
```nix
{ pkgs ? import <nixpkgs> {} }:

import <dewclaw> {
  inherit pkgs;
  configuration = ./config.nix;
}
```

All `openwrt` device configurations listed in `config.nix` will be built, each producing a stand-alone deployment script, and provided in a single nix output.

## Deploying a configuration

Building the provided example produces an output with a single deployment script, `deploy-example`, that can be run without arguments to deploy to the assigned target and reboot the device.
The deployment process on the device will take a snapshot of the current device configuration, apply changes as needed to satisfy the new configuration, and wait for confirmation that the new configuration is acceptable.
The deployment script provides this confirmation by reconnecting to the device after it has rebooted, if this reconnection succeeds the configuration is accepted.

After a reboot the device will wait for a set amount of time before automatically rolling back to the previous configuration.

### Reload-only deployment

Deploy scripts also accept a `--reload` argument to instruct the device to only reload UCI configuration instead of rebooting.
This is faster and less disruptive but may have unintended side-effects on services that are not properly configured by OpenWRT's `reload_config` and should thus be used with care.
Despite not rebooting to apply the configuration this mode also takes a snapshot and performs a rollback if no confirmation is provided.

[sops]: https://github.com/getsops/sops
