# Claude in Konsole tabs. Sourced from ~/.bashrc (line added by install.sh).
# Leaving an interactive claude session (/exit) closes the tab too, unless claude failed. Only for
# plain interactive runs typed at a prompt: not -p/--print, --version, --help or subcommands.
# A session ended by claude-restart (/restart) is resumed instead: its id is in ~/.cache/claude/restart/<this shell's pid>.
# Interactive sessions in the workspace start with their own --model (lib/session-model: cockpit.json "models",
# else the current default), so /model in one session doesn't move the others along.
claude() {
  local args=("$@") rc m="$HOME/.cache/claude/restart/$$" x skip a model
  if [[ -z $1 || $1 == -* ]] && [[ " $* " != *" --model "* && " $* " != *" --model="* ]]; then
    model=$("${BASH_SOURCE[0]%/*}/../lib/session-model" 2>/dev/null) && [[ -n $model ]] && args=(--model "$model" "${args[@]}")
  fi
  while :; do
    command claude "${args[@]}"; rc=$?
    [[ -f $m ]] || break
    a=(); skip=
    for x in "${args[@]}"; do   # same flags, minus the old --resume / --continue
      if [[ $skip ]]; then skip=; continue; fi
      case $x in --resume|-r) skip=1 ;; --resume=*|-c|--continue) ;; *) a+=("$x") ;; esac
    done
    args=("${a[@]}" --resume "$(<"$m")"); rm -f "$m"
  done
  if [[ $- == *i* && -t 0 && -n $KONSOLE_DBUS_SESSION && $rc -eq 0 && ( -z $1 || $1 == -* ) ]]; then
    case " $* " in *" -p "*|*" --print "*|*" -v "*|*" --version "*|*" -h "*|*" --help "*) ;; *) exit 0 ;; esac
  fi
  return $rc
}
# Links and file paths clickable (Ctrl+click), incl. OSC 8 links: also set per tab, since a running Konsole
# doesn't reload the cockpit profiles (lib/konsole-color) that carry the same settings.
[[ $- == *i* && -t 1 && -n $KONSOLE_VERSION ]] && printf '\e]50;AllowEscapedLinks=true;UnderlineFilesEnabled=true;UnderlineLinksEnabled=true\a'
# Claude Code only emits OSC 8 links for terminals it knows; Konsole isn't one of them.
[[ -n $KONSOLE_VERSION ]] && export FORCE_HYPERLINK=1
# A tab opened by the dashboard starts claude: the dashboard writes this folder into the marker
# just before opening the tab (Konsole's D-Bus can't run commands in a tab); a second line names a
# session to resume (one that was waiting with a question when its process ended).
_m="$HOME/.cache/claude/autostart"
if [[ $- == *i* && -f $_m && $(head -n1 "$_m") == "$PWD" && $(( $(date +%s) - $(stat -c %Y "$_m") )) -lt 15 ]]; then
  _r=$(sed -n 2p "$_m"); rm -f "$_m"; unset _m
  if [[ -n $_r ]]; then claude --resume "$_r"; else claude; fi
fi
unset _m _r
# A tab opened by session-name.sh (no dashboard in the window yet) runs the dashboard
_m="$HOME/.cache/claude/dashstart"
if [[ $- == *i* && -f $_m && $(head -n1 "$_m") == "$PWD" && $(( $(date +%s) - $(stat -c %Y "$_m") )) -lt 15 ]]; then
  : > "$_m"; dashboard
fi
unset _m
