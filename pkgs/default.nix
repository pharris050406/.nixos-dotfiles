final: prev: {
  dlmusic = final.callPackage ./dlmusic { };
  trace = final.callPackage ./trace { };
  ksa = final.callPackage ./ksa.nix { };
  blender-luxcore = final.callPackage ./blender-luxcore.nix { };
  sinkvol = final.callPackage ./sinkvol { };
}
