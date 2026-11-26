{
  buildFHSEnv,
  writeShellScript,
  dotnetCorePackages,
}:
let
  dotnet = dotnetCorePackages.runtime_10_0;
in
buildFHSEnv {
    name = "ksa";
    targetPkgs = p: with p; [
      dotnet
      vulkan-loader libGL
      glfw                      # harmless if KSA bundles its own
      xorg.libX11 xorg.libXcursor xorg.libXrandr xorg.libXi
      xorg.libXinerama xorg.libXext
      libxkbcommon wayland
      icu openssl zlib          # .NET runtime deps
      alsa-lib libpulseaudio
      stdenv.cc.cc.lib
    ];
    profile = ''
      export DOTNET_ROOT=${dotnet}/share/dotnet
      # export XDG_SESSION_TYPE=x11
    '';
    runScript = writeShellScript "ksa-run" ''
	  cd "$HOME/Games/ksa/" || exit 1
	  exec ./KSA "$@"
	'';
  }
