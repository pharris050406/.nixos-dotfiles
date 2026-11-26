{config, pkgs, inputs, ...}:
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
			ncd = "cd ${config.home.homeDirectory}/.nixos-dotfiles";
		};
	};

	home.file.".config/sway".source = ./config-files/sway;
	home.file.".config/quickshell".source = ./config-files/quickshell;
	home.file.".config/nvim".source = ./config-files/nvim;
	home.file.".config/foot".source = ./config-files/foot;
	programs.firefox.enable=true;
	# add packages
	home.packages = with pkgs;[
		ripgrep
		grim
		slurp
		satty
		btop
		quickshell
		mpc
		rmpc
		dlmusic
		ffmpeg
		swayfx
		autotiling
		wmenu
		
		trace
		blender-luxcore
		(python3.withPackages (ps: with ps; [ numpy scipy pillow ]))
		wl-clipboard
		libnotify
		brightnessctl
		cloudflared

		imagemagick
		
		libreoffice
		steam
		ksa

	];
	home.pointerCursor = {
	  enable=true;
	  package = pkgs.adwaita-icon-theme;
	  name = "Adwaita";
	  size = 16;
	  gtk.enable = true;
	};
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
				  "AndroidPlaylists" = {
					path = "${config.home.homeDirectory}/.android_playlists";
					devices = [ "p-bsd" ];
				  };
			};
		};
	};
	
   xdg.configFile."trace/trace.qml".source = ./config-files/trace/trace.qml;
	systemd.user.targets.sway-session.Unit = {
	  Description = "sway session";
	  BindsTo = [ "graphical-session.target" ];
	  Wants = [ "graphical-session-pre.target" ];
	  After = [ "graphical-session-pre.target" ];
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
