# sway session: dotfiles, bar, cursor, xdg dirs.
{
  config,
  libs,
  pkgs,
  ...
}:
let
  home = config.home.homeDirectory;
in
{
  home.file.".config/sway".source = ../../config-files/sway;
  home.file.".config/quickshell".source = ../../config-files/quickshell;
  home.file.".config/nvim".source = ../../config-files/nvim;
  home.file.".config/foot".source = ../../config-files/foot;
  xdg.configFile."trace/trace.qml".source = ../../config-files/trace/trace.qml;

  home.packages = with pkgs; [
    autotiling
    quickshell
    wmenu
    grim
    slurp
    satty
    wl-clipboard
    libnotify
    brightnessctl
    trace
    sinkvol
  ];

  # sway is started by hand from tty1, so graphical-session.target never comes
  # up on its own; sway's config starts this target, which pulls it in.
  systemd.user.targets.sway-session.Unit = {
    Description = "sway session";
    BindsTo = [ "graphical-session.target" ];
    Wants = [ "graphical-session-pre.target" ];
    After = [ "graphical-session-pre.target" ];
  };

  xdg.userDirs = {
    enable = true;
    createDirectories = true;
    pictures = "${home}/Pictures";
    music = "${home}/Music";
    download = "${home}/Downloads";
    documents = "${home}/Documents";
    # don't want these folders, so point them at home
    templates = home;
    publicShare = home;
    desktop = home;

    extraConfig = {
      XDG_PLAYLISTS_DIR = "${config.xdg.userDirs.music}/Playlists";
      XDG_SCREENSHOTS_DIR = "${config.xdg.userDirs.pictures}/Screenshots";
      XDG_WALLPAPERS_DIR = "${config.xdg.userDirs.pictures}/Wallpapers";
      XDG_GAMES_DIR = "${home}/Games";
    };
  };
}
