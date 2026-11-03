#!/usr/bin/env bash
# UserPromptSubmit hook: bring the git repo of the session's folder up to date with what other machines
# pushed. At most once a minute per repo, in the background (the prompt never waits for the network); what a
# pull brought in is told to Claude on the next prompt. The fetch gives up after a few seconds (SSH in
# batch mode, so a locked key fails at once). Fast-forward only: a repo with local commits is left for the
# sync job, and so are incoming files that have local changes here. Claude is told what came in.
# When the workspace repo itself moved, cockpit.json "after_pull" (a command relative to the workspace) runs
# with the changed files on stdin, e.g. to clone new repos. Log: ~/.cache/claude/repo-pull.log
. "$(dirname "$(readlink -f "$0")")/../lib/env.sh"
cwd=$(jq -r '.cwd // empty')
[ -d "$cwd" ] || exit 0
top=$(git -C "$cwd" rev-parse --show-toplevel 2>/dev/null) || exit 0
branch=$(git -C "$top" symbolic-ref --short HEAD 2>/dev/null) || exit 0
git -C "$top" remote get-url origin >/dev/null 2>&1 || exit 0

cache="$HOME/.cache/claude/repo-pull"; mkdir -p "$cache"
log="$HOME/.cache/claude/repo-pull.log"
stamp="$cache/$(printf %s "$top" | md5sum | cut -c1-16)"
# Report what the previous background pull of this repo brought in, once
[ -s "$stamp.news" ] && { cat "$stamp.news"; rm -f "$stamp.news"; }
[ -f "$stamp" ] && [ $(( $(date +%s) - $(stat -c %Y "$stamp") )) -lt 60 ] && exit 0
touch "$stamp"

say() {   # $1 = context for Claude, $2 = one line for the user; kept for the next prompt
  jq -nc --arg c "$1" --arg m "$2" '{systemMessage: $m, hookSpecificOutput: {hookEventName: "UserPromptSubmit", additionalContext: $c}}' > "$stamp.news"
}
pull() {
exec 9>"$(git -C "$top" rev-parse --absolute-git-dir)/repo-pull.lock"; flock -n 9 || exit 0
name=${top#"$ws"/}; [ "$top" = "$ws" ] && name=$ws_name
up="refs/remotes/origin/$branch"
GIT_SSH_COMMAND="ssh -o BatchMode=yes -o ConnectTimeout=3" GIT_TERMINAL_PROMPT=0 \
  timeout 5 git -C "$top" fetch -q origin "$branch" 2>>"$log" || { echo "$(date -Is) $top: fetch failed" >>"$log"; exit 0; }
git -C "$top" merge-base --is-ancestor "$up" HEAD && exit 0                     # nothing new
if ! git -C "$top" merge-base --is-ancestor HEAD "$up"; then
  echo "$(date -Is) $top: local commits, left for the sync job" >>"$log"; exit 0
fi
incoming=$(git -C "$top" diff --name-only HEAD "$up")
overlap=$(LC_ALL=C comm -12 <(LC_ALL=C sort <<<"$incoming") \
                   <({ git -C "$top" diff --name-only HEAD; git -C "$top" ls-files -o --exclude-standard; } | LC_ALL=C sort -u))
if [ -n "$overlap" ]; then
  echo "$(date -Is) $top: not pulled, local changes to incoming files: $overlap" >>"$log"
  sha=$(git -C "$top" rev-parse "$up")
  [ "$(cat "$stamp.held" 2>/dev/null)" = "$sha" ] && exit 0                   # said so already
  echo "$sha" > "$stamp.held"
  say "Git: another machine pushed changes to files that have local changes here, so they were not pulled (the sync job merges them later): $(paste -sd, <<<"$overlap" | sed 's/,/, /g')" \
      "git: $name not pulled (local changes to incoming files)"
  exit 0
fi
old=$(git -C "$top" rev-parse HEAD)
git -C "$top" merge -q --ff-only "$up" >>"$log" 2>&1 || { echo "$(date -Is) $top: fast-forward failed" >>"$log"; exit 0; }
echo "$(date -Is) $top: $old -> $(git -C "$top" rev-parse HEAD)" >>"$log"
if [ "$top" = "$ws" ]; then
  after=$(jq -r '.after_pull // empty' "$conf" 2>/dev/null)
  [ -n "$after" ] && (cd "$ws" && timeout 60 $after <<<"$incoming" >>"$log" 2>&1)
fi
n=$(git -C "$top" rev-list --count "$old..HEAD")
say "Git: since the last prompt, pulled $n commit(s) from another machine into $top: $(git -C "$top" log --format=%s "$old..HEAD" | head -5 | paste -sd';' | sed 's/;/; /g'). Changed files: $(head -30 <<<"$incoming" | paste -sd, | sed 's/,/, /g'). Re-read any of them you had read before." \
    "git: pulled $n commit(s) into $name"
}
( pull ) </dev/null >/dev/null 2>>"$log" &
exit 0
