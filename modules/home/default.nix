# home-manager config for p, shared by every host.
{
  imports = [
    ./shell.nix
    ./desktop.nix
    ./media.nix
    ./apps.nix
    ./firefox.nix
  ];

  home.username = "p";
  home.homeDirectory = "/home/p";
  home.stateVersion = "26.05";
}
