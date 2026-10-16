# space.fish — matches the Quickshell "mission control" theme (Theme.qml)
# Drop in ~/.config/fish/conf.d/ (or source from config.fish)

status is-interactive; or return

# ── palette (Theme.qml) ───────────────────────────────────────────
set -l bg      181825
set -l fg      cdd6f4
set -l muted   585b70
set -l teal    81c8be   # accent1
set -l blue    8caaee   # accent2
set -l green   a6d189   # accent3
set -l yellow  e5c890   # accent4
set -l peach   ef9f76   # accent5
set -l red     e78284   # accent6
set -l mauve   ca9ee6   # accent7
set -l sel     313244   # between bg and muted, for highlights

# ── syntax highlighting ───────────────────────────────────────────
set -g fish_color_normal          $fg
set -g fish_color_command         $blue
set -g fish_color_keyword         $mauve
set -g fish_color_param           $fg
set -g fish_color_option          $teal
set -g fish_color_quote           $green
set -g fish_color_escape          $mauve
set -g fish_color_redirection     $teal
set -g fish_color_operator        $teal
set -g fish_color_end             $peach
set -g fish_color_error           $red
set -g fish_color_comment         $muted --italics
set -g fish_color_autosuggestion  $muted
set -g fish_color_valid_path      --underline
set -g fish_color_cancel          $red
set -g fish_color_selection       --background=$sel
set -g fish_color_search_match    --background=$sel
set -g fish_color_history_current $yellow
set -g fish_color_cwd             $blue
set -g fish_color_user            $teal
set -g fish_color_host            $mauve

# ── completion pager ──────────────────────────────────────────────
set -g fish_pager_color_progress            $muted
set -g fish_pager_color_prefix              $teal --bold
set -g fish_pager_color_completion          $fg
set -g fish_pager_color_description         $muted
set -g fish_pager_color_selected_background --background=$sel
set -g fish_pager_color_selected_prefix     $teal --bold
set -g fish_pager_color_selected_completion $fg

# ── git (builtin fish_git_prompt) ─────────────────────────────────
set -g __fish_git_prompt_showdirtystate 1
set -g __fish_git_prompt_showuntrackedfiles 1
set -g __fish_git_prompt_char_stateseparator ''
set -g __fish_git_prompt_char_dirtystate '*'
set -g __fish_git_prompt_char_stagedstate '+'
set -g __fish_git_prompt_char_untrackedfiles '?'
set -g __fish_git_prompt_color_branch $mauve
set -g __fish_git_prompt_color_dirtystate $yellow
set -g __fish_git_prompt_color_stagedstate $green
set -g __fish_git_prompt_color_untrackedfiles $muted

# ── greeting ──────────────────────────────────────────────────────
function fish_greeting
    set_color 585b70
    prompt_hostname
    set_color normal
end

# ── prompt ────────────────────────────────────────────────────────
#   ~/src/foo  main*  T+4.2s  ✕ 1
#   ›
function fish_prompt
    set -l last $status

    echo
    set_color 8caaee
    echo -n (prompt_pwd -D 2)

    fish_git_prompt '  %s'

    # mission-clock style duration for anything that took ≥ 2s
    if test "$CMD_DURATION" -ge 2000 2>/dev/null
        set -l s (math -s1 "$CMD_DURATION / 1000")
        set -l t "$s"s
        if test $CMD_DURATION -ge 60000
            set t (math -s0 "$CMD_DURATION / 60000")m(math -s0 "($CMD_DURATION % 60000) / 1000")s
        end
        set_color e5c890
        echo -n "  T+$t"
    end

    if test $last -ne 0
        set_color e78284
        echo -n "  ✕ $last"
    end

    echo
    if test $last -eq 0
        set_color 81c8be
    else
        set_color e78284
    end
    echo -n '› '
    set_color normal
end
