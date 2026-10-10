if status is-interactive
    set -g fish_greeting

    # Apply the palette generated from Nyvorel's active wallpaper.
    if test -f ~/.local/state/quickshell/user/generated/terminal/sequences.txt
        cat ~/.local/state/quickshell/user/generated/terminal/sequences.txt
    end
    if test -f ~/.local/state/nyvorel/terminal-startup-overlay.fish
        source ~/.local/state/nyvorel/terminal-startup-overlay.fish
    end

    if type -q starship
        starship init fish | source
    end
    if type -q zoxide
        zoxide init fish | source
    end
    if type -q fzf
        fzf --fish | source
    end
end
