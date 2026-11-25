{ config, lib, pkgs, ... }:{
  imports =
    [

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
  # tty1 login starts sway right away (bash is your login shell; foot runs fish)
	programs.bash.loginShellInit = ''
	  if [ -z "$WAYLAND_DISPLAY" ] && [ "$XDG_VTNR" = 1 ]; then
		export XDG_CURRENT_DESKTOP=sway XDG_SESSION_TYPE=wayland
		exec sway
	  fi
	'';

	# login screen only asks for your password (username already filled in as p)
	services.getty = {
	  extraArgs = [ "--skip-login" ];
	  loginOptions = "-p -- p";
	};

	# no boot menu wait (systemd-boot otherwise waits 5 s)
	boot.loader.timeout = 0;
  services.flatpak.enable = true;
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

  services.mullvad-vpn={
	enable=true;
  };
  # Define a user account. Don't forget to set a password with ‘passwd’.
  users.users.p = {
    isNormalUser = true;
    extraGroups = [ "wheel" "networkmanager" "dialout" ]; # Enable ‘sudo’ for the user.
    packages = with pkgs; [
      tree

    ];
  };
	boot.loader.systemd-boot.consoleMode = "0";
  # programs.firefox.enable = true;
  nixpkgs.config.allowUnfree=true;

  # PlatformIO's udev rules (board permissions + stops ModemManager grabbing ports)
  services.udev.packages = [ pkgs.platformio-core.udev ];

  environment.systemPackages = with pkgs; [
    neovim # Do not forget to add an editor to edit configuration.nix! The Nano editor is also installed by default.
    wget
	zip
	unzip
    git
	gnumake
	gcc
	clang-tools
	lua-language-server
	tinymist
	emmet-language-server
	pkg-config
    foot
	easyeffects

    # VSCode inside an FHS sandbox so PlatformIO's downloaded toolchains run
    (pkgs.vscode.fhsWithPackages (ps: with ps; [ python3 ]))
  ];
  programs.direnv.enable = true;
  fonts.packages = with pkgs;[
    nerd-fonts.jetbrains-mono
	twitter-color-emoji
  ];


  nix.settings.experimental-features = [ "nix-command" "flakes" ];

  system.stateVersion = "26.05"; # Did you read the comment?

}
