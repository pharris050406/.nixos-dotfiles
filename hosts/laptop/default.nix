{ ... }: {
  imports = [
    ./hardware-configuration.nix
    ./speaker-eq.nix
    ./eq-autoswitch.nix
  ];

  home-manager.users.p.home.pointerCursor = {
    enable = true;
    package = pkgs.adwaita-icon-theme;
    name = "Adwaita";
    size = 16;
    gtk.enable = true;
  };
  environment.etc."sway/config.d/laptop.conf".text = ''
    seat seat0 xcursor_theme Adwaita 16
  '';
}
