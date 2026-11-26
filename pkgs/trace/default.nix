{ writeScriptBin }:
writeScriptBin "trace" (builtins.readFile ./trace)
