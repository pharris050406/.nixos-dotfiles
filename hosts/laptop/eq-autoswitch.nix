# Laptop: the speaker EQ is only for the speakers. The 3.5 mm jack is a second
# port on the same ALSA device, so when headphones are plugged in, make the
# plain device the default (no EQ); when they're unplugged, go back to the EQ.
# Leaves the default alone if you've picked something else (Bluetooth, USB).
{ pkgs, ... }:
let
  hw = "alsa_output.pci-0000_00_1f.3.analog-stereo";
  eq = "effect_input.fw13_eq";

  eq-autoswitch = pkgs.writeShellApplication {
    name = "eq-autoswitch";
    runtimeInputs = with pkgs; [ pulseaudio gawk ];
    text = ''
      HW=${hw}
      EQ=${eq}

      apply() {
        cur=$(pactl get-default-sink)
        [ "$cur" = "$HW" ] || [ "$cur" = "$EQ" ] || return 0

        port=$(pactl list sinks | awk -v n="$HW" '
          $1 == "Name:" { f = ($2 == n) }
          f && $1 == "Active" && $2 == "Port:" { print $3; exit }')

        case $port in
          *headphones*) want=$HW ;;
          *)            want=$EQ ;;
        esac
        [ "$cur" = "$want" ] || pactl set-default-sink "$want"
      }

      apply
      # port changes show up as sink/card change events
      pactl subscribe | while read -r line; do
        case $line in
          *"on sink"* | *"on card"*) apply ;;
        esac
      done
    '';
  };
in
{
  home-manager.users.p.systemd.user.services.eq-autoswitch = {
    Unit = {
      Description = "Bypass the speaker EQ when headphones are plugged in";
      After = [ "pipewire-pulse.service" "wireplumber.service" ];
    };
    Service = {
      ExecStart = "${eq-autoswitch}/bin/eq-autoswitch";
      Restart = "on-failure";
      RestartSec = 2;
    };
    Install.WantedBy = [ "default.target" ];
  };
}
