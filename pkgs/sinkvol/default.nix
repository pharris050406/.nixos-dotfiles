{
  writeShellApplication,
  wireplumber,
  pipewire,
  jq,
  gnused,
}:
writeShellApplication {
  name = "sinkvol";
  runtimeInputs = [
    wireplumber
    pipewire
    jq
    gnused
  ];
  text = builtins.readFile ./sinkvol;
}
