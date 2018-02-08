with import <nixpkgs> {};

pkgs.haskellPackages.callCabal2nix "tech-test" ./. {}
