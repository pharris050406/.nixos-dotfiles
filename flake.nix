{
	description = "nixos";
	inputs={
		nixpkgs.url="nixpkgs/nixos-unstable";
		home-manager={
			url="github:nix-community/home-manager";
			inputs.nixpkgs.follows="nixpkgs";
		};
		fusion360 = {
			url = "github:lukasl-dev/fusion360.nix/3d196a8ad251ebdcaae14afde7320d3022d30f45";
			inputs.nixpkgs.follows = "nixpkgs";
		};
	};

	outputs={self, nixpkgs, home-manager, ...}@inputs:{
		nixosConfigurations.laptop=nixpkgs.lib.nixosSystem{
			system="x86_64-linux";
			specialArgs = { inherit inputs; };
			modules=[
				./configuration.nix
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
	};
}
