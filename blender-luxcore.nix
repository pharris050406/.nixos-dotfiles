# Blender + LuxCoreRender for NixOS / home-manager.
#
#   home.packages = [ (pkgs.callPackage ./blender-luxcore.nix { }) ];
#
# nixpkgs' Blender, plus:
#   * pyluxcore 2.11.2: LuxCore's official PyPI wheel, autoPatchelf'd so it
#     finds libstdc++ / libgcc_s / libatomic, on Blender's PYTHONPATH;
#   * BlendLuxCore 2.11.1, installed as a read-only *system* extension.
# The add-on normally pip-downloads pyluxcore on start-up; nixpkgs' Blender has
# no pip, so that step fails harmlessly and it imports the copy above.
# BlendLuxCore 2.11 supports Blender 4.5 LTS and 5.2 LTS (nixos-unstable: 5.2.x).
{
  lib,
  stdenv,
  stdenvNoCC,
  blender,
  fetchurl,
  fetchFromGitHub,
  autoPatchelfHook,
  makeWrapper,
  symlinkJoin,
}:

let
  wheels = {
    "3.12" = {
      url = "https://files.pythonhosted.org/packages/04/0e/5c290e5084cf31f28e3fd42ee0eda87962ce6abef4acf811e6abacf3e83b/pyluxcore-2.11.2-cp312-cp312-manylinux_2_28_x86_64.whl";
      hash = "sha256-HR+asfhqiC+pW7XoowqHZ5SqyyAVWwSNOIgPMU/faeE=";
    };
    "3.13" = {
      url = "https://files.pythonhosted.org/packages/c3/6e/8a342da1a562e969ce3b10a6320de113c8a2bb3e19f01e34af4d234ebdd4/pyluxcore-2.11.2-cp313-cp313-manylinux_2_28_x86_64.whl";
      hash = "sha256-RGnX4EDPdqiqpdfYOsgii7Thqwsnx2IfqJXh6L2x6K0=";
    };
    "3.14" = {
      url = "https://files.pythonhosted.org/packages/75/eb/b64a756eac8c1fa35cdbaa5a33c6330489f18a46a4e0670d7a24045a5c39/pyluxcore-2.11.2-cp314-cp314-manylinux_2_28_x86_64.whl";
      hash = "sha256-azKiaaNvLXAF6rgCSmuamJPPd3IkBDWwdt/JIKZGJI4=";
    };
  };

  pyluxcore =
    ps:
    ps.buildPythonPackage {
      pname = "pyluxcore";
      version = "2.11.2";
      format = "wheel";
      src = fetchurl (
        wheels.${ps.python.pythonVersion}
          or (throw "pyluxcore 2.11.2 has no wheel for Python ${ps.python.pythonVersion}")
      );
      nativeBuildInputs = [ autoPatchelfHook ];
      buildInputs = [ stdenv.cc.cc.lib ]; # libstdc++, libgcc_s, libatomic
      # the wheel declares nvidia-cuda-nvrtc, needed only for CUDA rendering
      dontCheckRuntimeDeps = true;
    };

  # The add-on mkdir()s wheels/ and wheels_backup/ in its own folder at
  # start-up, so they must already exist in the read-only store path.
  blendluxcore = stdenvNoCC.mkDerivation {
    pname = "blendluxcore";
    version = "2.11.1";
    src = fetchFromGitHub {
      owner = "LuxCoreRender";
      repo = "BlendLuxCore";
      rev = "v2.11.1";
      hash = "sha256-K6DfbnMgcQtBjNbaw89uvaHbJYVRJJZHonYj1MLAOzY=";
    };
    dontBuild = true;
    installPhase = ''
      mkdir -p $out/system/blendluxcore
      cp -r . $out/system/blendluxcore/
      mkdir -p $out/system/blendluxcore/wheels $out/system/blendluxcore/wheels_backup
    '';
  };
in
symlinkJoin {
  name = "blender-luxcore-${blender.version}";
  paths = [ (blender.withPackages (ps: [ (pyluxcore ps) ])) ];
  nativeBuildInputs = [ makeWrapper ];
  postBuild = ''
    wrapProgram $out/bin/blender \
      --set BLENDER_SYSTEM_EXTENSIONS ${blendluxcore}
  '';
  meta = {
    description = "Blender with the LuxCoreRender engine (BlendLuxCore) ready to use";
    mainProgram = "blender";
    platforms = [ "x86_64-linux" ];
  };
}
