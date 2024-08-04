{ config, lib, ... }:

{
  imports = [
    ./qemu-ga.nix
    ./statistics.nix
  ];
}
