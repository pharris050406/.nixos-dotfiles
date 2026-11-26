{ config, lib, pkgs, ... }: {
  imports = [ ./hardware-configuration.nix ];

  #loads the nvidia kernel module even though there's no X server
  services.xserver.videoDrivers = [ "nvidia" ];
  
  hardware.nvidia = {
    modesetting.enable = true;
    open = true;
    package = config.boot.kernelPackages.nvidiaPackages.stable;
    powerManagement.enable = true;
    nvidiaSettings=false;
    
   }; 
    environment.sessionVariables={
      SWAY_UNSUPPORTED_GPU = "1";
      __NV_DISABLE_EXPLICIT_SYNC = "1";
    };

	services.openssh.enable = true;
  }
