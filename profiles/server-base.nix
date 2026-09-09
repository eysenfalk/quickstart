{ pkgs, ... }:
{
  home.packages = with pkgs; [
    bind.dnsutils
    btop
    htop
    iproute2
    lsof
    netcat-openbsd
    tmux
  ];

  programs.tmux = {
    enable = true;
    clock24 = true;
    keyMode = "vi";
    terminal = "screen-256color";
  };
}
