with import <nixpkgs> {};
with lib;

let

  src = builtins.filterSource (path: type:
    !(hasPrefix "." (baseNameOf path)) &&
    (baseNameOf path != "run-nodes") &&
    !(hasSuffix ".nix" path) &&
    (baseNameOf path == "nixops" -> type != "directory"))
    ./.;

in pkgs.haskellPackages.callCabal2nix "tech-test" src {}
