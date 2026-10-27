{ config, lib, pkgs, ... }:{
  imports =
    [
      ./hardware-configuration.nix
    ];
  hardware.graphics={
	enable=true;
	enable32Bit=true;
  };
  hardware.bluetooth={
	enable = true;
	powerOnBoot = true;
  };

  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  # Use latest kernel.
  boot.kernelPackages = pkgs.linuxPackages_latest;

  networking.hostName = "p-laptop"; # Define your hostname.

  # Configure network connections interactively with nmcli or nmtui.
  networking.networkmanager = {
	enable = true;
	wifi.macAddress = "random";
	wifi.scanRandMacAddress = true;

  };
  # networking.wireless = {
  #    enable = true;
  #    userControlled = true;
  #    allowAuxiliaryImperativeNetworks = true;
  #  };

  time.timeZone = "America/Los_Angeles";

  # Enable CUPS to print documents.
  # services.printing.enable = true;

  # Enable sound.
  # services.pulseaudio.enable = true;
  # OR
  security.rtkit.enable = true;
  services.pipewire = {
    enable = true;
	pulse.enable=true;
	alsa.enable = true;
    alsa.support32Bit = true;
  };
  services.flatpak.enable = true;
  xdg.portal={
	enable = true;
	wlr.enable = true;
  };

  services.mullvad-vpn={
	enable=true;
  };
  # Define a user account. Don't forget to set a password with ‘passwd’.
  users.users.p = {
    isNormalUser = true;
    extraGroups = [ "wheel" "networkmanager" ]; # Enable ‘sudo’ for the user.
    packages = with pkgs; [
      tree

    ];
  };

  # programs.firefox.enable = true;
  nixpkgs.config.allowUnfree=true;
  environment.systemPackages = with pkgs; [
    neovim # Do not forget to add an editor to edit configuration.nix! The Nano editor is also installed by default.
    wget
    git
	gnumake
	gcc
	clang-tools
	lua-language-server
	tinymist
	emmet-language-server
	pkg-config
    foot
  ];
  programs.direnv.enable = true;
  fonts.packages = with pkgs;[
    nerd-fonts.jetbrains-mono
	twitter-color-emoji
  ];


  nix.settings.experimental-features = [ "nix-command" "flakes" ];

  system.stateVersion = "26.05"; # Did you read the comment?

}

