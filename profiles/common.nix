{ pkgs, ... }:
{
  home = {
    packages = with pkgs; [
      bat
      curl
      eza
      fd
      git
      jq
      ripgrep
      rsync
      tree
      unzip
      wget
      zip
    ];

    sessionVariables = {
      EDITOR = "nvim";
      VISUAL = "nvim";
    };
  };

  programs = {
    bash = {
      enable = true;
      enableCompletion = true;
      shellAliases = {
        ll = "eza --long --all --group-directories-first";
        la = "eza --all --group-directories-first";
      };
    };

    git = {
      enable = true;
      settings = {
        init.defaultBranch = "main";
        pull.rebase = false;
      };
    };

    neovim = {
      enable = true;
      defaultEditor = true;
      viAlias = true;
      vimAlias = true;
    };
  };
}
