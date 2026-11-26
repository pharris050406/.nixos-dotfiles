# System config shared by every host. Host-specific bits live in hosts/<name>/.
{
  imports = [
    ./base.nix
    ./session.nix
    ./dev.nix
  ];
}
