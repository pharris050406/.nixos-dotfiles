{
  writeShellApplication,
  quickshell,
  swaylock,
  procps,
  util-linux,
  coreutils,
}:
writeShellApplication {
  name = "lockscreen";
  runtimeInputs = [
    quickshell
    swaylock
    procps
    util-linux
    coreutils
  ];
  text = builtins.readFile ./lockscreen;
}
