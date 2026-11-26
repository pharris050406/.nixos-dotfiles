{ lib, pkgs, ... }:
let
  settings = {
    # tabs / startup
    "browser.ctrlTab.sortByRecentlyUsed" = true;   # Ctrl+Tab in recently-used order
    "browser.startup.homepage" = "chrome://browser/content/blanktab.html";
    "browser.newtabpage.enabled" = false;          # blank new tab
    "browser.fullscreen.autohide" = false;         # keep toolbars in fullscreen
    "general.autoScroll" = true;                   # middle-click autoscroll

    # address bar
    "browser.urlbar.suggest.quicksuggest.all" = false;   # no Firefox Suggest
    "browser.urlbar.suggest.history" = false;
    "browser.urlbar.suggest.engines" = false;
    "browser.urlbar.suggest.quickactions" = false;

    # no prefetching / speculative connections
    "network.dns.disablePrefetch" = true;
    "network.prefetch-next" = false;
    "network.http.speculative-parallel-limit" = 0;

    # optional
    # "layout.css.prefers-color-scheme.content-override" = 0;   # websites: dark
    # "dom.webgpu.enabled" = true;
  };

  userJs = pkgs.writeText "firefox-user.js" (lib.concatStrings (lib.mapAttrsToList
    (n: v: "user_pref(${builtins.toJSON n}, ${builtins.toJSON v});\n") settings));

  amo = slug: {
    install_url = "https://addons.mozilla.org/firefox/downloads/latest/${slug}/latest.xpi";
    installation_mode = "normal_installed";   # auto-installed; can be disabled, not removed
  };
in
{
  programs.firefox = {
    enable = true;
    policies.ExtensionSettings = {
      "uBlock0@raymondhill.net" = amo "ublock-origin";
      "sponsorBlocker@ajay.app" = amo "sponsorblock";
    };
  };

  # Profile folder names are random and differ per machine, so instead of
  # hardcoding them, link user.js into every profile that exists at switch
  # time. A profile created later picks it up on the next nrs.
  home.activation.firefoxUserJs = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    for d in "$HOME"/.config/mozilla/firefox/*/; do
      [ -f "$d/prefs.js" ] || continue
      run ln -sfn ${userJs} "$d/user.js"
    done
  '';
}
