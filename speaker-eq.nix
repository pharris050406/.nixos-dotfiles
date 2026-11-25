{ pkgs, ... }:
{
  services.pipewire.extraConfig.pipewire."90-fw13-eq" = {
    "context.modules" = [{
      name = "libpipewire-module-filter-chain";
      args = {
        "node.description" = "FW13 Speaker EQ";
        "media.name" = "FW13 Speaker EQ";
        "filter.graph" = {
          nodes = [
            {
              type = "builtin";
              name = "eq";
              label = "param_eq";
              config.filters = map (b: {
                type = "bq_peaking";
                freq = builtins.elemAt b 0;
                gain = builtins.elemAt b 1;
                q = 2.3521;
              }) [
                [ 39.11    6.0  ]
                [ 60.23    6.0  ]
                [ 92.75    6.0  ]
                [ 142.83   6.0  ]
                [ 219.95   6.0  ]
                [ 338.7    1.39 ]
                [ 521.58  (-2.03) ]
                [ 803.2   (-3.22) ]
                [ 1236.86 (-2.51) ]
                [ 1904.68 (-2.17) ]
                [ 2933.06 (-2.52) ]
                [ 4516.7  (-0.71) ]
                [ 6955.38  4.81 ]
                [ 10710.78 6.0  ]
                [ 16493.82 6.0  ]
              ];
            }
            {
              type = "ladspa";
              name = "limiter";
              plugin = "${pkgs.ladspaPlugins}/lib/ladspa/fast_lookahead_limiter_1913.so";
              label = "fastLookaheadLimiter";
              control = {
                "Input gain (dB)" = 0.0;
                "Limit (dB)" = 0.0;
                "Release time (s)" = 0.05;
              };
            }
          ];
          links = [
            { output = "eq:Out 1"; input = "limiter:Input 1"; }
            { output = "eq:Out 2"; input = "limiter:Input 2"; }
          ];
          inputs  = [ "eq:In 1" "eq:In 2" ];
          outputs = [ "limiter:Output 1" "limiter:Output 2" ];
        };
        "audio.channels" = 2;
        "audio.position" = [ "FL" "FR" ];
        "capture.props" = {
          "node.name" = "effect_input.fw13_eq";
          "media.class" = "Audio/Sink";
        };
        "playback.props" = {
          "node.name" = "effect_output.fw13_eq";
          "node.passive" = true;
        };
      };
    }];
  };
}
