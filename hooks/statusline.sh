#!/usr/bin/env bash
# Claude Code status line: model · context · rate limits · estimated cost
input=$(cat)
export LC_ALL=${LC_ALL:-C.UTF-8}  # count multibyte glyphs as one column

j() { jq -r "$1 // empty" <<<"$input"; }

RESET=$'\e[0m'; DIM=$'\e[2m'; BOLD=$'\e[1m'
GREEN=$'\e[32m'; YELLOW=$'\e[33m'; RED=$'\e[31m'; CYAN=$'\e[36m'
BLUE=$'\e[94m'; WHITE=$'\e[97m'

# Color by percentage: green < 50, yellow < 80, red otherwise
pct_color() {
  local p=${1:-0}
  if (( p < 50 )); then printf '%s' "$GREEN"
  elif (( p < 80 )); then printf '%s' "$YELLOW"
  else printf '%s' "$RED"; fi
}

# 10-cell bar, e.g. ▰▰▱▱▱▱▱▱▱▱
bar() {
  local p=${1:-0} filled i out=""
  filled=$(( (p + 5) / 10 )); (( filled > 10 )) && filled=10
  for (( i = 0; i < 10; i++ )); do
    if (( i < filled )); then out+="▰"; else out+="▱"; fi
  done
  printf '%s' "$out"
}

# 138961 -> 139k, 1000000 -> 1M
human() {
  local n=${1:-0}
  if (( n >= 1000000 )); then
    awk -v n="$n" 'BEGIN { v = n / 1000000; if (v == int(v)) printf "%dM", v; else printf "%.1fM", v }'
  elif (( n >= 1000 )); then printf '%dk' $(( (n + 500) / 1000 ))
  else printf '%d' "$n"; fi
}

# Reset time: clock time if today, weekday + time otherwise
reset_at() {
  local ts=$1
  [[ -z $ts ]] && return
  if [[ $(date -d "@$ts" +%F) == $(date +%F) ]]; then date -d "@$ts" +%H:%M
  else date -d "@$ts" '+%a %H:%M'; fi
}

SEP=" ${DIM}│${RESET} "
parts=()

# Model
model=$(j '.model.display_name')
[[ -n $model ]] && parts+=("${BOLD}${CYAN}${model}${RESET}")

# Context window
ctx_pct=$(j '.context_window.used_percentage')
if [[ -n $ctx_pct ]]; then
  ctx_used=$(jq -r '.context_window.current_usage
    | (.input_tokens // 0) + (.cache_creation_input_tokens // 0) + (.cache_read_input_tokens // 0)' <<<"$input")
  ctx_size=$(j '.context_window.context_window_size')
  c=$(pct_color "$ctx_pct")
  parts+=("${BLUE}ctx${RESET} ${c}$(bar "$ctx_pct") ${ctx_pct}%${RESET} ${DIM}$(human "$ctx_used")/$(human "$ctx_size")${RESET}")
fi

# Subscription rate limits (cached for the dashboard, which aligns its 5h/7d windows to them)
rl=$(jq -c '.rate_limits // empty' <<<"$input")
if [[ -n $rl ]]; then
  mkdir -p ~/.cache/claude && printf '%s\n' "$rl" > ~/.cache/claude/rate-limits.json
fi
now=$(date +%s)
for win in five_hour:5h:18000 seven_day:7d:604800; do
  IFS=: read -r key label span <<<"$win"
  p=$(j ".rate_limits.$key.used_percentage")
  [[ -z $p ]] && continue
  ts=$(j ".rate_limits.$key.resets_at")
  r=$(reset_at "$ts")
  c=$(pct_color "$p")
  # Pace: more than 5 points ahead of the share of the window already gone -> ▲ (at that rate the limit is hit early)
  pace=""
  if [[ $ts =~ ^[0-9]+$ ]] && (( ts > now )); then
    gone=$(( 100 - (ts - now) * 100 / span ))
    (( ${p%.*} > gone + 5 )) && pace=" ${YELLOW}▲${gone}%${RESET}"
  fi
  parts+=("${BLUE}${label}${RESET} ${c}${p}%${RESET}${pace}${r:+ ${WHITE}↻ ${r}${RESET}}")
done

# Estimated cost (API list price; not billed on a subscription)
cost=$(j '.cost.total_cost_usd')
[[ -n $cost ]] && parts+=("${YELLOW}~\$$(LC_NUMERIC=C printf '%.2f' "$cost")${RESET} ${DIM}est.${RESET}")

. "$(dirname "$(readlink -f "$0")")/../lib/env.sh"

out=""
for p in "${parts[@]}"; do
  [[ -n $out ]] && out+=$SEP
  out+=$p
done

# Big two-line logo of the project folder name in the tab colour on black, right-aligned in the empty space.
# Width comes from Claude's own terminal (the status line command has no tty itself).
term_cols() {
  local pid=$PPID tty i
  for (( i = 0; i < 6 && pid > 1; i++ )); do
    tty=$(ps -o tty= -p "$pid" 2>/dev/null | tr -d ' ')
    if [[ -n $tty && $tty != "?" ]]; then
      stty -F "/dev/$tty" size 2>/dev/null | awk '{ print $2 }'; return
    fi
    pid=$(ps -o ppid= -p "$pid" 2>/dev/null | tr -d ' ')
  done
}
cols=$(term_cols); cols=${cols:-${COLUMNS:-0}}
MARGIN=4  # Claude Code indents the status line; keep clear of the right edge
plain=$(sed $'s/\e\[[0-9;]*m//g' <<<"$out")

# Folder name as in the session/tab name: path relative to the workspace, e.g. "family/school"
# (the root itself is the workspace's name), otherwise the current directory's own name.
cwd=$(j '.workspace.current_dir'); cwd=${cwd:-$(j '.cwd')}; cwd=${cwd:-$PWD}
dir=$(ws_rel "$cwd"); dir=${dir:-$(basename "$cwd")}

# 2-row block font: top row / bottom row per character (unknown characters print as ▒)
declare -A T=(
  [a]="▄▀█" [b]="█▄▄" [c]="█▀▀" [d]="█▀▄" [e]="█▀▀" [f]="█▀▀" [g]="█▀▀" [h]="█ █" [i]="█"
  [j]="  █" [k]="█▄▀" [l]="█  " [m]="█▀▄▀█" [n]="█▄ █" [o]="█▀█" [p]="█▀█" [q]="█▀█" [r]="█▀█"
  [s]="█▀" [t]="▀█▀" [u]="█ █" [v]="█ █" [w]="█ █ █" [x]="▀▄▀" [y]="█▄█" [z]="▀█"
  [0]="█▀█" [1]="▄█" [2]="▀█" [3]="▀▀█" [4]="█ █" [5]="█▀" [6]="█▄▄" [7]="▀▀█" [8]="███" [9]="█▀█"
  [" "]="  " [.]=" " [-]="▄▄" [_]="  " [/]=" ▄▀"
)
declare -A B=(
  [a]="█▀█" [b]="█▄█" [c]="█▄▄" [d]="█▄▀" [e]="██▄" [f]="█▀ " [g]="█▄█" [h]="█▀█" [i]="█"
  [j]="█▄█" [k]="█ █" [l]="█▄▄" [m]="█ ▀ █" [n]="█ ▀█" [o]="█▄█" [p]="█▀▀" [q]="▀▀█" [r]="█▀▄"
  [s]="▄█" [t]=" █ " [u]="█▄█" [v]="▀▄▀" [w]="▀▄▀▄▀" [x]="█ █" [y]=" █ " [z]="█▄"
  [0]="█▄█" [1]=" █" [2]="█▄" [3]="▄██" [4]="▀▀█" [5]="▄█" [6]="█▄█" [7]="  █" [8]="█▄█" [9]="▀▀█"
  [" "]="  " [.]="▄" [-]="  " [_]="▄▄" [/]="▄▀ "
)
lower=${dir,,}
logo1=" "; logo2=" "
for (( k = 0; k < ${#lower}; k++ )); do
  ch=${lower:k:1}
  if [[ -v T[$ch] ]]; then logo1+="${T[$ch]} "; logo2+="${B[$ch]} "
  else logo1+="▒ "; logo2+="▒ "; fi
done
# Logo colour = the session's tab colour from cockpit.json; white when the folder has none. Always on black.
LOGO=$'\e[97;40m'
hex=$(ws_color "$dir"); hex=${hex#\#}
[[ $hex =~ ^[0-9A-Fa-f]{6}$ ]] && LOGO=$'\e[40;38;2;'"$((16#${hex:0:2}));$((16#${hex:2:2}));$((16#${hex:4:2}))m"
right=$(( cols - MARGIN - ${#logo1} ))  # column where the logo starts

# Every session open on this machine that has a question right now (state files of hooks/session-state.sh; a
# dead pid or one reused by another program doesn't count), by session name
asking=$(jq -r 'select(.state == "question" or .state == "input") | "\(.pid) \(.cwd)"' ~/.cache/claude/sessions/*.json 2>/dev/null |
  while read -r qpid qcwd; do
    [[ $(cat "/proc/$qpid/comm" 2>/dev/null) == claude ]] || continue
    start=$(jq -r '.cwd // empty' ~/.claude/sessions/"$qpid".json 2>/dev/null)   # the folder it started in, as in its name
    name=$(ws_rel "${start:-$qcwd}"); echo "${name:-$(basename "${start:-$qcwd}")}"
  done | sort -u | paste -sd, | sed 's/,/, /g')
[[ -n $asking ]] && asking="question: $asking"

if (( right >= ${#plain} + 1 )); then
  printf '%s%*s%s\n' "$out" $(( right - ${#plain} )) "" "${LOGO}${logo1}${RESET}"
  (( ${#asking} > right - 3 )) && asking="${asking:0:right-4}…"   # stays clear of the logo
  # Claude Code trims leading whitespace, so lead with a braille blank (U+2800): invisible, not trimmed
  printf '%s%*s%s\n' "${RESET}⠀${RED}${asking}${RESET}" $(( right - 1 - ${#asking} )) "" "${LOGO}${logo2}${RESET}"
else
  printf '%s\n' "$out"
  [[ -n $asking ]] && printf '%s\n' "${RED}${asking}${RESET}"
fi
