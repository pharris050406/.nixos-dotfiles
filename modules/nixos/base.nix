# Boot, hardware, networking, users, nix itself.
{ pkgs, ... }:
{
  boot.loader.systemd-boot.enable = true;
  boot.loader.systemd-boot.consoleMode = "0";
  boot.loader.efi.canTouchEfiVariables = true;
  boot.loader.timeout = 0; # no boot menu wait (systemd-boot otherwise waits 5 s)
  boot.kernelPackages = pkgs.linuxPackages_latest;

  hardware.graphics = {
    enable = true;
    enable32Bit = true;
  };
  hardware.bluetooth = {
    enable = true;
    powerOnBoot = true;
  };

  # nmcli / nmtui
  networking.networkmanager = {
    enable = true;
    wifi.macAddress = "random";
    wifi.scanRandMacAddress = true;
  };
  services.mullvad-vpn.enable = true;

  time.timeZone = "America/Los_Angeles";

  users.users.p = {
    isNormalUser = true;
    extraGroups = [
      "wheel"
      "networkmanager"
    ];
    packages = with pkgs; [ tree ];
  };

  environment.systemPackages = with pkgs; [
    neovim
    wget
    git
    zip
    unzip
  ];

  # zsh completions for system packages (zsh itself is set up in home-manager)
  environment.pathsToLink = [ "/share/zsh" ];

  nixpkgs.config.allowUnfree = true;
  nixpkgs.overlays = [ (import ../../pkgs) ];

  nix.settings.experimental-features = [
    "nix-command"
    "flakes"
  ];

  system.stateVersion = "26.05";
}
