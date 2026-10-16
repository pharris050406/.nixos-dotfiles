{config, pkgs, ...}:

{
	home.username="p";
	home.homeDirectory = "/home/p";
	programs.git.enable=true;
	home.stateVersion="26.05";
	programs.fish={
		enable=true;
		interactiveShellInit=builtins.readFile ./config-files/fish/space.fish;
		functions={
			nrs="sudo nixos-rebuild switch --flake ~/.nixos-dotfiles";
		};
	};

	home.file.".config/sway".source = ./config-files/sway;
	home.file.".config/quickshell".source = ./config-files/quickshell;
	home.file.".config/nvim".source = ./config-files/nvim;
	home.file.".config/foot".source = ./config-files/foot;
	programs.firefox.enable=true;

	home.packages = with pkgs;[
		ripgrep
		grim
		slurp
		btop
		quickshell
		mpc
		rmpc
		ffmpeg
		swayfx
		autotiling
		wmenu

		wl-clipboard
		libnotify
		brightnessctl
		cloudflared
		
		steam

	];

	services.mpd-mpris = {
		enable = true;
	};

	services.playerctld.enable = true;
	services.mpd = {
		enable = true;
		musicDirectory = "${config.home.homeDirectory}/Music";
		playlistDirectory = "${config.home.homeDirectory}/Music/Playlists";

		extraConfig = ''
					restore_paused		"yes"

					audio_output {
						type		"pipewire"
						name		"Pipewire Output"
						mixer_type	"software"
					}
				'';
	};
	services.syncthing={
		enable=true;
		settings = {
			devices = {
				"p-bsd" = {
					id = "OCGJR4O-KS6VXHQ-OERYZEI-W2UK27R-YXAHTXS-FUTPEHU-6XQLKYY-7CT3WQ2";
				};
			};
			folders = {
				"Music" = {
					path = config.xdg.userDirs.music;
					devices = [ "p-bsd" ];
				};
			};
		};
	};

	xdg.userDirs = {
		enable = true;
		createDirectories = true;
		pictures = "${config.home.homeDirectory}/Pictures";
		music = "${config.home.homeDirectory}/Music";
		download = "${config.home.homeDirectory}/Downloads";
		documents = "${config.home.homeDirectory}/Documents";

		extraConfig = {
			XDG_PLAYLISTS_DIR = "${config.xdg.userDirs.music}/Playlists";
			XDG_SCREENSHOTS_DIR = "${config.xdg.userDirs.pictures}/Screenshots";
			XDG_WALLPAPERS_DIR = "${config.xdg.userDirs.pictures}/Wallpapers";
			XDG_GAMES_DIR = "${config.home.homeDirectory}/Games";
		};
		# i don't want these folders so i just point them to home
		templates = "${config.home.homeDirectory}";
		publicShare = "${config.home.homeDirectory}";
		desktop = "${config.home.homeDirectory}";
	};
}
