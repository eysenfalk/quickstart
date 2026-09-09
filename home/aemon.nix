{ ... }:
{
  imports = [
    ../profiles/common.nix
    ../profiles/server-base.nix
  ];

  home = {
    username = "aemon";
    homeDirectory = "/home/aemon";
    stateVersion = "26.05";
  };

  programs.home-manager.enable = true;
}
