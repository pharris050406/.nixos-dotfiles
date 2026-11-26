# Music: mpd + clients, MPRIS, syncthing to p-bsd.
{ config, pkgs, ... }:
{
  home.packages = with pkgs; [
    mpc
    rmpc
    dlmusic
    ffmpeg
  ];

  services.mpd = {
    enable = true;
    musicDirectory = config.xdg.userDirs.music;
    playlistDirectory = "${config.xdg.userDirs.music}/Playlists";
    extraConfig = ''
      restore_paused "yes"

      audio_output {
        type       "pipewire"
        name       "Pipewire Output"
        mixer_type "software"
      }
    '';
  };
  services.mpd-mpris.enable = true;
  services.playerctld.enable = true;

  services.syncthing = {
    enable = true;
    settings = {
      devices."p-bsd".id = "OCGJR4O-KS6VXHQ-OERYZEI-W2UK27R-YXAHTXS-FUTPEHU-6XQLKYY-7CT3WQ2";
      folders = {
        "Music" = {
          path = config.xdg.userDirs.music;
          devices = [ "p-bsd" ];
        };
        "AndroidPlaylists" = {
          path = "${config.home.homeDirectory}/.android_playlists";
          devices = [ "p-bsd" ];
        };
      };
    };
  };
}
