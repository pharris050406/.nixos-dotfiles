{
  writeShellApplication,
  spotdl,
  yt-dlp,
  ffmpeg,
  jq,
  curl,
  mpc,
  python3,
  coreutils,
  findutils,
  gnused,
}:
writeShellApplication {
  name = "dlmusic";
  runtimeInputs = [
    spotdl yt-dlp ffmpeg jq curl mpc python3
    coreutils findutils gnused
  ];
  excludeShellChecks = [ "SC2016" "SC1003" ];
  text = builtins.readFile ./dlmusic;
}
