# Screen lock: the Quickshell lock screen (config-files/quickshell/lock.qml),
# via the `lockscreen` script, which falls back to swaylock if it ever fails.
# Locks after 5 min idle and before every sleep (closing the lid suspends, so
# that locks too); screens go off after 10 min. $mod+Escape locks by hand.
# Fullscreen windows (videos) hold off the idle timer: see the sway config.
{ pkgs, ... }:
let
  lock = "${pkgs.lockscreen}/bin/lockscreen";
  swaymsg = "${pkgs.swayfx}/bin/swaymsg";
in
{
  home.packages = [ pkgs.lockscreen ];

  # The fallback, in the same colours.
  programs.swaylock = {
    enable = true;
    settings = {
      color = "181825";
      font = "JetBrainsMono Nerd Font";
      indicator-radius = 90;
      indicator-thickness = 3;
      ignore-empty-password = true;
      show-failed-attempts = true;

      inside-color = "00000000";
      inside-clear-color = "00000000";
      inside-ver-color = "00000000";
      inside-wrong-color = "00000000";
      line-color = "00000000";
      line-clear-color = "00000000";
      line-ver-color = "00000000";
      line-wrong-color = "00000000";
      separator-color = "00000000";

      ring-color = "585b70";
      ring-clear-color = "e5c890";
      ring-ver-color = "8caaee";
      ring-wrong-color = "e78284";
      key-hl-color = "a6d189";
      bs-hl-color = "e78284";

      text-color = "cdd6f4";
      text-clear-color = "e5c890";
      text-ver-color = "8caaee";
      text-wrong-color = "e78284";
    };
  };

  services.swayidle = {
    enable = true;
    systemdTargets = [ "sway-session.target" ];
    events = {
      before-sleep = lock;
      lock = lock;
    };
    timeouts = [
      {
        timeout = 300;
        command = lock;
      }
      {
        timeout = 600;
        command = "${swaymsg} 'output * power off'";
        resumeCommand = "${swaymsg} 'output * power on'";
      }
    ];
  };
}
