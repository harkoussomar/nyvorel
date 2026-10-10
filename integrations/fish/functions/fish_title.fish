# ==============================================================
# fish_title — metadata bridge for Kitty's native developer bar
#
# This does NOT draw the bar. It only publishes project metadata
# through Kitty's tab title. ~/.config/kitty/tab_bar.py renders it.
# No tmux, no mouse interception, no scrollback interception.
# ==============================================================

function __ii_devbar_project_root
    set -l root (command git rev-parse --show-toplevel 2>/dev/null)
    if test -n "$root"
        printf '%s' "$root"
    else
        printf '%s' "$PWD"
    end
end

function __ii_devbar_short --argument-names text max_len
    if test -z "$text"
        return
    end

    if test (string length -- "$text") -le $max_len
        printf '%s' "$text"
    else
        set -l keep (math "$max_len - 1")
        printf '%s…' (string sub -s 1 -l $keep -- "$text")
    end
end

function fish_title
    # Machine-readable title consumed by Kitty's custom tab bar.
    # Git refs cannot contain ':', therefore '::' is a safe separator
    # for the branch field as well.
    set -l branch ""
    set -l changes ""
    set -l ahead "0"
    set -l behind "0"
    set -l runtime ""
    set -l package_manager ""
    set -l location (path basename "$PWD")
    set -l project_root (__ii_devbar_project_root)

    if test -z "$location"
        set location "/"
    end

    # ----------------------------------------------------------
    # Git
    # ----------------------------------------------------------
    if command git rev-parse --is-inside-work-tree >/dev/null 2>&1
        set branch (command git branch --show-current 2>/dev/null)
        if test -z "$branch"
            set branch (command git rev-parse --short HEAD 2>/dev/null)
        end
        set branch (__ii_devbar_short "$branch" 34)

        set changes (command git status --porcelain=v1 --untracked-files=normal 2>/dev/null | count)

        if command git rev-parse --abbrev-ref '@{upstream}' >/dev/null 2>&1
            # upstream...HEAD => left = behind, right = ahead
            set -l counts (command git rev-list --left-right --count '@{upstream}...HEAD' 2>/dev/null | string match -ra '[0-9]+')
            if test (count $counts) -ge 2
                set behind $counts[1]
                set ahead $counts[2]
            end
        end
    end

    # ----------------------------------------------------------
    # Runtime / package manager
    # ----------------------------------------------------------
    if test -f "$project_root/package.json"
        if command -q node
            set runtime " "(command node --version 2>/dev/null)
        end

        if test -f "$project_root/pnpm-lock.yaml"
            set package_manager "󰏗 pnpm"
        else if test -f "$project_root/bun.lock" -o -f "$project_root/bun.lockb"
            set package_manager " bun"
        else if test -f "$project_root/yarn.lock"
            set package_manager "󰏗 yarn"
        else if test -f "$project_root/package-lock.json"
            set package_manager "󰏗 npm"
        end
    else if test -f "$project_root/pyproject.toml" -o -f "$project_root/requirements.txt" -o -f "$project_root/Pipfile"
        if command -q python
            set -l pyv (command python --version 2>/dev/null | string replace 'Python ' '')
            if test -n "$pyv"
                set runtime " py $pyv"
            end
        end
        if set -q VIRTUAL_ENV
            set package_manager "󰆧 "(path basename "$VIRTUAL_ENV")
        end
    else if test -f "$project_root/Cargo.toml"
        if command -q rustc
            set -l rv (command rustc --version 2>/dev/null | string split ' ')[2]
            if test -n "$rv"
                set runtime " $rv"
            end
        end
        set package_manager "󰏗 cargo"
    else if test -f "$project_root/go.mod"
        if command -q go
            set -l gv (command go version 2>/dev/null | string split ' ')[3] | string replace -r '^go' ''
            if test -n "$gv"
                set runtime " $gv"
            end
        end
    else if test -f "$project_root/pom.xml" -o -f "$project_root/build.gradle" -o -f "$project_root/build.gradle.kts"
        if command -q java
            set -l jv (command java -version 2>&1 | head -n1 | string match -r '"[^"]+"' | string trim -c '"')
            if test -n "$jv"
                set runtime " $jv"
            end
        end
    end

    # Prefix + eight fields. Kitty's tab_bar.py parses this.
    printf 'NYVOREL_DEVBAR::%s::%s::%s::%s::%s::%s::%s::%s' \
        "$branch" "$changes" "$ahead" "$behind" \
        "$runtime" "$package_manager" "$location" "$project_root"
end
