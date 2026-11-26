# Everything else.
{ pkgs, ... }:
{
  home.packages = with pkgs; [
    ripgrep
    btop
    imagemagick
    cloudflared
    (python3.withPackages (
      ps: with ps; [
        numpy
        scipy
        pillow
      ]
    ))

    libreoffice
    blender-luxcore
    steam
    ksa
  ];
}
