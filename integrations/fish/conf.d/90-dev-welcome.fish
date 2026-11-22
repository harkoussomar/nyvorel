if status is-interactive
    function welcome --description 'Show the Nyvorel terminal welcome'
        set -l helper "$HOME/.local/bin/nyvorel-terminal-welcome"
        if test -x "$helper"
            command "$helper" $argv
        end
    end

    if test "$PWD" = "$HOME"; and test -r "$HOME/.local/state/quickshell/user/generated/colors.json"
        welcome
    end
end
