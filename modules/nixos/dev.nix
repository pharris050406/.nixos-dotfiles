# Compilers, language servers, embedded (PlatformIO).
{ pkgs, ... }:
{
  environment.systemPackages = with pkgs; [
    gnumake
    gcc
    pkg-config
    clang-tools
    lua-language-server
    tinymist
    emmet-language-server

    # VSCode inside an FHS sandbox so PlatformIO's downloaded toolchains run
    (vscode.fhsWithPackages (ps: with ps; [ python3 ]))
  ];

  # PlatformIO's udev rules (board permissions + stops ModemManager grabbing ports)
  services.udev.packages = [ pkgs.platformio-core.udev ];
  users.users.p.extraGroups = [ "dialout" ]; # serial ports
}
