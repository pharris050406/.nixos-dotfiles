{
	description = "nixos";
	inputs={
		nixpkgs.url="nixpkgs/nixos-unstable";
		home-manager={
			url="github:nix-community/home-manager";
			inputs.nixpkgs.follows="nixpkgs";
		};
	};

	outputs={self, nixpkgs, home-manager, ...}@inputs:
		let
			mkHost = name: nixpkgs.lib.nixosSystem{
				system="x86_64-linux";
				specialArgs = { inherit inputs; };
				modules=[
					./configuration.nix
					./hosts/${name}
					{ networking.hostName = name; }
					home-manager.nixosModules.home-manager{
						home-manager={
							useGlobalPkgs=true;
							useUserPackages=true;
							extraSpecialArgs = { inherit inputs; };
							users.p = import ./home.nix;
							backupFileExtension="backup";
						};
					}
				];
			};
		in{
			nixosConfigurations = {
				laptop = mkHost "laptop";
				desktop = mkHost "desktop";
			};
	};
}
