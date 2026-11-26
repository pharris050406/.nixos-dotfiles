# zsh, git, direnv.
{ pkgs, ... }:
{
  programs.zsh = {
    enable = true;
    autosuggestion.enable = true;
    syntaxHighlighting.enable = true;
    history = {
      size = 50000;
      save = 50000;
      ignoreDups = true;
      ignoreSpace = true; # a leading space keeps a command out of history
      share = true;
    };
    shellAliases = {
      nrs = "sudo nixos-rebuild switch --flake ~/.nixos-dotfiles";
      ncd = "cd ~/.nixos-dotfiles";
      ls = "ls --color=auto";
      grep = "grep --color=auto";
      diff = "diff --color=auto";
      ip = "ip -color=auto";
    };
    initContent = ''
      bindkey -e                # emacs keys, even if $EDITOR is vim

      # dir in blue; the % turns red when the last command failed
      PROMPT='%F{blue}%~%f %(?.%#.%F{red}%#%f) '

      # LS_COLORS for ls and the completion menu
      eval "$(${pkgs.coreutils}/bin/dircolors -b)"
      zstyle ':completion:*' menu select
      zstyle ':completion:*' list-colors ''${(s.:.)LS_COLORS}

      # window title: the running command, or the current dir when idle (like fish did)
      autoload -Uz add-zsh-hook
      _title_idle() { print -Pn '\e]2;%~\a' }
      _title_cmd()  { print -n '\e]2;'; print -rn -- "$1"; print -n '\a' }
      add-zsh-hook precmd  _title_idle
      add-zsh-hook preexec _title_cmd
    '';
  };

  programs.git.enable = true;

  # hooks into zsh; nix-direnv caches `use flake` environments
  programs.direnv = {
    enable = true;
    nix-direnv.enable = true;
  };
}
