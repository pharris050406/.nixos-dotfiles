# Graphical session: autologin into sway, audio, portals, fonts.
{ pkgs, ... }:
{
  programs.sway = {
    enable = true;
    package = pkgs.swayfx;
    extraPackages = [ ]; # don't pull in the default foot/dmenu/swaylock set
  };
  security.pam.services.swaylock = { };
  security.pam.services.quickshell-lock = { };

  # tty1 login starts sway right away (bash is the login shell; foot runs zsh)
  programs.bash.loginShellInit = ''
    if [ -z "$WAYLAND_DISPLAY" ] && [ "$XDG_VTNR" = 1 ]; then
      export XDG_CURRENT_DESKTOP=sway XDG_SESSION_TYPE=wayland
      exec sway
    fi
  '';

  # login screen only asks for the password (username already filled in as p)
  services.getty = {
    extraArgs = [ "--skip-login" ];
    loginOptions = "-p -- p";
  };

  security.rtkit.enable = true;
  services.pipewire = {
    enable = true;
    pulse.enable = true;
    alsa.enable = true;
    alsa.support32Bit = true;
  };

  xdg.portal = {
    enable = true;
    wlr.enable = true;
    extraPortals = [ pkgs.xdg-desktop-portal-gtk ];
    config.common = {
      default = [ "gtk" ];
      "org.freedesktop.impl.portal.Screenshot" = [ "wlr" ];
      "org.freedesktop.impl.portal.ScreenCast" = [ "wlr" ];
    };
  };

  services.flatpak.enable = true;

  fonts.packages = with pkgs; [
    nerd-fonts.jetbrains-mono
    twitter-color-emoji
  ];

  environment.systemPackages = with pkgs; [ foot ];
}
