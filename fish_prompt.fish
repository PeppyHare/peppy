function visual_length --description\
    "Return visual length of string, i.e. without terminal escape sequences"
    # TODO: Use "string replace" builtin in Fish 2.3.0
    printf $argv | perl -pe 's/\x1b.*?[mGKH]//g' | wc -m
end

function echo_color --description\
    "Echo last arg with color specified by earlier args for set_color"
    set s $argv[-1]
    set -e argv[-1]
    set_color $argv
    echo -n $s
    set_color normal
    echo
end

# Inspired from:
# https://github.com/jonmosco/kube-ps1
# https://github.com/Ladicle/fish-kubectl-prompt

function print_fish_colors --description 'Shows the various fish colors being used'
    set -l clr_list (set -n | grep fish | grep color | grep -v __)
    if test -n "$clr_list"
        set -l bclr (set_color normal)
        set -l bold (set_color --bold)
        printf "\n| %-38s | %-38s |\n" Variable Definition
        echo '|¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯|¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯|'
        for var in $clr_list
            set -l def $$var
            set -l clr (set_color $def ^/dev/null)
            or begin
                printf "| %-38s | %s%-38s$bclr |\n" "$var" (set_color --bold white --background=red) "$def"
                continue
            end
            printf "| $clr%-38s$bclr | $bold%-38s$bclr |\n" "$var" "$def"
        end
        echo '|________________________________________|________________________________________|'\n
    end
end

function __kube_ps_update_cache
    function __kube_ps_cache_context
        set -l ctx (kubectl config current-context | cut -d'/' -f1 2>/dev/null)
        if /bin/test $status -eq 0
            set -g __kube_ps_context "$ctx"
        else
            set -g __kube_ps_context "n/a"
        end
    end
  
    function __kube_ps_cache_namespace
        set -l ns (kubectl config view --minify -o 'jsonpath={..namespace}' 2>/dev/null)
        if /bin/test -n "$ns"
          set -g __kube_ps_namespace "$ns"
        else
          set -g __kube_ps_namespace "default"
        end
    end
  
    set -l kubeconfig "$KUBECONFIG"
    if /bin/test -z "$kubeconfig"
        set kubeconfig "$HOME/.kube/config"
    end
  
    if /bin/test "$kubeconfig" != "$__kube_ps_kubeconfig"
        __kube_ps_cache_context
        __kube_ps_cache_namespace
        set -g __kube_ps_kubeconfig "$kubeconfig"
        set -g __kube_ps_timestamp (date +%s)
        return
    end
  
    for conf in (string split ':' "$kubeconfig")
        if /bin/test -r "$conf"
            if /bin/test -z "$__kube_ps_timestamp"; or /bin/test (/usr/bin/stat -f '%m' "$conf") -gt "$__kube_ps_timestamp"
                __kube_ps_cache_context
                __kube_ps_cache_namespace
                set -g __kube_ps_kubeconfig "$kubeconfig"
                set -g __kube_ps_timestamp (date +%s)
                return
            end
        end
    end
end

function __kube_prompt
    if /bin/test -z "$__kube_ps_enabled"; or /bin/test $__kube_ps_enabled -ne 1
      return
    end

    __kube_ps_update_cache
    if [ "$__kube_ps_context" != "n/a" ]
        echo -n -s " (⎈ $__kube_ps_context|$__kube_ps_namespace)"
    end
end


function _append --no-scope-shadowing
    set $argv[1] "$$argv[1]""$argv[2]"
end

function __tmux_prompt
    set multiplexer (_is_multiplexed)
  
    switch $multiplexer
        case screen
            set pane (_get_screen_window)
        case tmux
            set pane (_get_tmux_window)
     end
  
    set_color 666666
    if test -z $pane
        echo -n ""
    else
        echo -n $pane' | '
    end
end

function _get_tmux_window
    tmux lsw | grep active | sed 's/\*.*$//g;s/: / /1' | awk '{ print $2 "-" $1 }' -
end

function _get_screen_window
    set initial (screen -Q windows; screen -Q echo "")
    set middle (echo $initial | sed 's/  /\n/g' | grep '\*' | sed 's/\*\$ / /g')
    echo $middle | awk '{ print $2 "-" $1 }' -
end

function _is_multiplexed
    set multiplexer ""
    if test -z $TMUX
    else
        set multiplexer "tmux"
    end
    if test -z $WINDOW
    else
        set multiplexer "screen"
    end
    echo $multiplexer
end

function __print_duration
    set -l duration $argv[1]
   
    set -l millis  (math $duration % 1000)
    set -l seconds (math -s0 $duration / 1000 % 60)
    set -l minutes (math -s0 $duration / 60000 % 60)
    set -l hours   (math -s0 $duration / 3600000 % 60)
   
    if test $duration -lt 60000;
        # Below a minute
        printf "%d.%03ds\n" $seconds $millis
    else if test $duration -lt 3600000;
        # Below a hour
        printf "%02d:%02d.%03d\n" $minutes $seconds $millis
    else
        # Everything else
        printf "%02d:%02d:%02d.%03d\n" $hours $minutes $seconds $millis
    end
end
function _convertsecs
  printf "%02d:%02d:%02d\n" (math -s0 $argv[1] / 3600) (math -s0 (math $argv[1] \% 3600) / 60) (math -s0 $argv[1] \% 60)
end

function fish_prompt
    # Cache exit status
    set -l last_status $status
  
    # Just calculate these once, to save a few cycles when displaying the prompt
    if not set -q __fish_prompt_hostname
      set -g __fish_prompt_hostname (hostname|cut -d . -f 1)
    end
    if not set -q __fish_prompt_char
        switch (id -u)
          case 0
        set -g __fish_prompt_char '#'
          case '*'
        set -g __fish_prompt_char 'λ'
        end
    end

#    Setup colors
#    use extended color pallete if available
#    if [[ $terminfo[colors] -ge 256 ]]; then
#        turquoise="%F{81}"
#        orange="%F{166}"
#        purple="%F{135}"
#        hotpink="%F{161}"
#        limegreen="%F{118}"
#    else
#        turquoise="%F{cyan}"
#        orange="%F{yellow}"
#        purple="%F{magenta}"
#        hotpink="%F{red}"
#        limegreen="%F{green}"
#    fi
    set -l normal (set_color normal)
    set -l white (set_color normal --bold)
    set -l turquoise (set_color 5fdfff)
    set -l orange (set_color df5f00)
    set -l hotpink (set_color df005f --bold)
    set -l blue (set_color blue)
    set -l limegreen (set_color 87ff00)
    set -l purple (set_color af5fff)
   
    # Configure __fish_git_prompt
    set -g __fish_git_prompt_char_stateseparator ' '
    set -g __fish_git_prompt_color 5fdfff --bold
    set -g __fish_git_prompt_color_flags df5f00
    set -g __fish_git_prompt_color_prefix white
    set -g __fish_git_prompt_color_suffix white
    set -g __fish_git_prompt_showdirtystate true
    set -g __fish_git_prompt_showuntrackedfiles true
    set -g __fish_git_prompt_showstashstate true
    set -g __fish_git_prompt_show_informative_status true 
    set -g __fish_git_prompt_showupstream true
  
    set -l current_user (whoami)

    if test $CMD_DURATION
        # Show duration of the last command in seconds
        set duration (echo "$CMD_DURATION 1000" | awk '{printf "%.3fs", $1 / $2}')
    end

    # Line 1
    set -l left_prompt $white'╭─'$hotpink$current_user$white' in '$limegreen(pwd|sed "s=$HOME=~=")$turquoise
    _append left_prompt (__kube_prompt " (%s)")
    _append left_prompt (__fish_git_prompt " (%s)")
    set -l right_prompt " $last_status ($duration) "
    _append right_prompt (date "+%H:%M:%S")
    set -l left_length (visual_length $left_prompt)
    set -l right_length (visual_length $right_prompt)
    set -l spaces (math "$COLUMNS - $left_length - $right_length")
  
    # display first line
    echo -n $left_prompt
    # printf $turquoise"%-"$spaces"s" " " | tr ' ' '-'
    printf $turquoise"%-"$spaces"s" " "
    echo $right_prompt
  
    # Line 2
    echo -n $white'╰'
    # support for virtual env name
    if set -q VIRTUAL_ENV
        echo -n "($turquoise"(basename "$VIRTUAL_ENV")"$white)"
    end
    echo -n $white'─'$__fish_prompt_char $normal
end


