{ config, lib, pkgs, ... }: {
  imports = [ ./hardware-configuration.nix ];

  #loads the nvidia kernel module even though there's no X server
  servuces.xserver.videoDrivers = [ "nvidia" ];
  
  hardware.nvidia = {
    modesetting.enable = true;
    open = true;
    package = config.boot.kernelPackages.nvidiaPackages.stable;
    powerManagment.enable = true;
    nvidiaSettings=false;
    
   }; 
    boot.kernelPackages = lib.mkForce pkgs.linuxPackages;
    environment.sessionVariables={
      SWAY_UNSUPPORTED_GPU = "1";
      __NV_DISABLE_EXPLICIT_SYNC = "1";
    };
  }
