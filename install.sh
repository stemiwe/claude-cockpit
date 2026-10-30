#!/usr/bin/env bash
# Installs the cockpit for the current user; safe to re-run (e.g. after moving the cockpit).
#   ./install.sh [workspace]     workspace defaults to the cockpit's parent folder
# - links bin/ into ~/.local/bin, hooks/ into ~/.claude/hooks, the status line to ~/.claude/statusline.sh
# - registers the hooks, the status line and the mods in plugins/ (env CLAUDE_CODE_PLUGIN_DIRS) in
#   ~/.claude/settings.json (adds what is missing, drops mods removed from plugins/)
# - installs and starts the systemd user timer claude-jobs.timer and the service cockpit-web.service
#   (restarted, so it runs the current code)
# - sources shell/bashrc.sh from ~/.bashrc
# - adds the launchers claude-cockpit and claude-dashboard (desktop files + icons); with cockpit.json
#   "pin_launchers": true pins them to the first two taskbar slots
# - remembers the workspace in ~/.config/claude-cockpit/workspace
# - rules: if <workspace>/rules/ (or cockpit.json "rules": "<folder>") is missing, starts your own from
#   rules/cockpit.md (plus an empty RULES.md, new git repo); with $CLAUDE_RULES_REPO set it asks whether to
#   clone that ruleset instead (answer ahead with CLAUDE_RULES=shared|own). Makes sure the workspace's
#   CLAUDE.md loads @<that folder>/RULES.md.
set -euo pipefail
here=$(cd "$(dirname "$(readlink -f "$0")")" && pwd)
ws=$(cd "${1:-$here/..}" && pwd)
mkdir -p ~/.local/bin
# the cockpit calls qdbus6 (Debian/Ubuntu name); other distros name it differently, e.g. Fedora qdbus-qt6
if ! command -v qdbus6 >/dev/null; then
  for q in qdbus-qt6 /usr/lib64/qt6/bin/qdbus /usr/lib/qt6/bin/qdbus; do
    q=$(command -v "$q" || true)
    [ -n "$q" ] && { ln -sfn "$q" ~/.local/bin/qdbus6; echo "linked ~/.local/bin/qdbus6 -> $q"; break; }
  done
fi
for cmd in jq python3 qdbus6; do command -v "$cmd" >/dev/null || echo "warning: $cmd not found (needed by the cockpit)" >&2; done

mkdir -p ~/.config/claude-cockpit ~/.local/bin ~/.claude/hooks ~/.config/systemd/user
echo "$ws" > ~/.config/claude-cockpit/workspace
[ -f "$ws/cockpit.json" ] || cp "$here/cockpit.example.json" "$ws/cockpit.json"

rd=$(jq -r '.rules // "rules"' "$ws/cockpit.json" 2>/dev/null); rd=${rd:-rules}   # the rules folder, relative to the workspace
rules_repo=${CLAUDE_RULES_REPO:-}
if [ ! -f "$ws/$rd/RULES.md" ]; then
  choice=${CLAUDE_RULES:-own}
  if [ -n "$rules_repo" ] && [ -z "${CLAUDE_RULES:-}" ] && [ -t 0 ]; then
    echo "Rules for the sessions (<workspace>/$rd/):"
    echo "  1) use the shared ruleset ($rules_repo)"
    echo "  2) create your own (starts from the cockpit conventions)"
    read -rp "Choice [1/2]: " choice
  fi
  case "$choice" in
    1|shared) git clone -q "$rules_repo" "$ws/$rd" && echo "cloned the rules into $ws/$rd" ;;
    *)
      mkdir -p "$ws/$rd"; cp "$here/rules/cockpit.md" "$ws/$rd/"
      printf '# Rules\n\nRules for every Claude session in this workspace.\n\n@cockpit.md\n' > "$ws/$rd/RULES.md"
      git -C "$ws/$rd" init -q -b main && echo "created your own rules in $ws/$rd (push them to a repo of yours)" ;;
  esac
fi
if [ -f "$ws/$rd/RULES.md" ] && ! grep -qxF "@$rd/RULES.md" "$ws/CLAUDE.md" 2>/dev/null; then
  if grep -qxE "@(cockpit|rules)/RULES.md" "$ws/CLAUDE.md" 2>/dev/null; then sed -i "s#^@\(cockpit\|rules\)/RULES.md\$#@$rd/RULES.md#" "$ws/CLAUDE.md"
  else printf '\n@%s/RULES.md\n' "$rd" >> "$ws/CLAUDE.md"; fi
  echo "$ws/CLAUDE.md now loads @$rd/RULES.md"
fi

for f in "$here"/bin/*; do ln -sfn "$f" ~/.local/bin/"$(basename "$f")"; done
for f in session-name.sh session-state.sh sort-tabs.sh cockpit-pull.sh repo-pull.sh; do ln -sfn "$here/hooks/$f" ~/.claude/hooks/$f; done
rm -f ~/.claude/hooks/clear-prompt.sh   # dropped hook
ln -sfn "$here/hooks/statusline.sh" ~/.claude/statusline.sh
# launchers with their own taskbar icons (the windows' Wayland app id = desktop file name): the sessions and the dashboard
mkdir -p ~/.local/share/applications ~/.local/share/icons/hicolor/scalable/apps
# cockpit.json "icons": {"cockpit": "<svg/png>", "dashboard": "…"} (paths relative to the workspace) replaces an icon
for app in claude-cockpit claude-dashboard; do
  own=$(jq -r --arg k "${app#claude-}" '.icons[$k] // empty' "$ws/cockpit.json" 2>/dev/null)
  src="$here/icons/$app.svg"; [ -n "$own" ] && [ -f "$ws/$own" ] && src="$ws/$own"
  rm -f ~/.local/share/icons/hicolor/scalable/apps/$app.*
  ln -sfn "$src" ~/.local/share/icons/hicolor/scalable/apps/$app.${src##*.}
done
desktop() {   # file name, Name, Comment, Exec; Icon as a full path (the taskbar doesn't always find it by name)
  local icon; icon=$(ls ~/.local/share/icons/hicolor/scalable/apps/"$1".* 2>/dev/null | head -n1)
  printf '[Desktop Entry]\nType=Application\nName=%s\nComment=%s\nExec=%s\nIcon=%s\nStartupWMClass=%s\nTerminal=false\nCategories=Development;\n' \
    "$2" "$3" "$4" "${icon:-$1}" "$1" > ~/.local/share/applications/"$1".desktop
}
label=$(jq -r '.name // empty' "$ws/cockpit.json" 2>/dev/null); label=${label:-Claude}   # launcher names: the workspace's name
desktop claude-cockpit "$label" "Claude Code sessions of the workspace (opens the root session)" "$HOME/.local/bin/cockpit"
desktop claude-dashboard "$label dashboard" "Live view of every project" "$HOME/.local/bin/dashboard --window"
command -v kbuildsycoca6 >/dev/null && kbuildsycoca6 >/dev/null 2>&1 || true
# cockpit.json "pin_launchers": true pins both to the first two slots of every Plasma task manager (each run)
if [ "$(jq -r '.pin_launchers // false' "$ws/cockpit.json" 2>/dev/null)" = true ] && command -v qdbus6 >/dev/null; then
  qdbus6 org.kde.plasmashell /PlasmaShell org.kde.PlasmaShell.evaluateScript '
    const pins = ["applications:claude-cockpit.desktop", "applications:claude-dashboard.desktop"];
    panels().forEach(p => p.widgets().forEach(w => {
      if (w.type.indexOf("taskmanager") < 0 && w.type.indexOf("icontasks") < 0) return;
      w.currentConfigGroup = ["General"];
      let l = w.readConfig("launchers", []);
      l = (Array.isArray(l) ? l : String(l).split(",")).filter(x => x && pins.indexOf(x) < 0);
      w.writeConfig("launchers", pins.concat(l));
      w.reloadConfig();
    }));' >/dev/null 2>&1 && echo "pinned the launchers to the taskbar" || echo "warning: could not pin the launchers (Plasma not running?)" >&2
fi
"$here/lib/konsole-color" --profiles '#FF0096'   # tab colour profiles (Konsole without setTabColor); #FF0096 = dashboard

# settings.json: one hook entry per event, added only if no entry runs that command yet
settings=~/.claude/settings.json
[ -f "$settings" ] || echo '{}' > "$settings"
tmp=$(mktemp)
plugins=$(for d in "$here"/plugins/*/; do [ -d "$d" ] && echo "${d%/}"; done | jq -R . | jq -s .)
jq --argjson plugins "$plugins" --arg dir "$here" '
  def add(ev; cmd): .hooks[ev] = ((.hooks[ev] // []) as $h
    | if any($h[]?.hooks[]?; .command == cmd) then $h else $h + [{hooks: [{type: "command", command: cmd}]}] end);
  add("SessionStart"; "~/.claude/hooks/session-name.sh")
  | reduce ("UserPromptSubmit", "PostToolUse", "Notification", "Stop", "SessionEnd") as $ev
      (.; add($ev; "~/.claude/hooks/session-state.sh"))
  | add("UserPromptSubmit"; "~/.claude/hooks/cockpit-pull.sh")
  | add("UserPromptSubmit"; "~/.claude/hooks/repo-pull.sh")
  | .hooks.UserPromptSubmit |= map(select(all(.hooks[]?; .command != "~/.claude/hooks/clear-prompt.sh")))   # dropped hook
  | .statusLine //= {type: "command", command: "~/.claude/statusline.sh", refreshInterval: 30}
  | .env.CLAUDE_CODE_PLUGIN_DIRS = ((.env.CLAUDE_CODE_PLUGIN_DIRS // "" | split(":")
      | map(select(. != "" and (startswith($dir + "/plugins/") | not) or (. as $d | $plugins | index($d))))) as $have
      | $have + ($plugins - $have) | join(":"))
' "$settings" > "$tmp"
if ! cmp -s "$tmp" "$settings"; then cp "$settings" "$settings.bak"; mv "$tmp" "$settings"; echo "updated $settings (backup: settings.json.bak)"
else rm -f "$tmp"; fi

cp "$here"/systemd/claude-jobs.{service,timer} "$here"/systemd/cockpit-web.service ~/.config/systemd/user/
systemctl --user daemon-reload
systemctl --user enable --now claude-jobs.timer >/dev/null
systemctl --user enable cockpit-web.service >/dev/null 2>&1; systemctl --user restart cockpit-web.service

line="[ -f \"$here/shell/bashrc.sh\" ] && . \"$here/shell/bashrc.sh\"   # claude cockpit"
touch ~/.bashrc
grep -v '# claude cockpit$' ~/.bashrc > "$tmp" || true
echo "$line" >> "$tmp"
cmp -s "$tmp" ~/.bashrc || cat "$tmp" > ~/.bashrc
rm -f "$tmp"

echo "cockpit installed for workspace $ws"
