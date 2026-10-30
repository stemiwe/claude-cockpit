# Claude cockpit

A terminal cockpit for running many Claude Code sessions side by side, one per project, in KDE Konsole tabs.

- **Dashboard** (`dashboard`): a full-screen TUI with one row per project. Each row shows the tab colour,
  the live state (busy / question / monitoring), the project's `Status:` line, the last tool call of a running
  session ("bash: git push", "edit: lib.php") and tokens used (5h / 7d / all time). Click a project to switch to its tab, or to open a new tab that starts `claude`. Press 1–9 to
  dismiss a question row (marks it idle, no tokens used). `q` quits. Starting `claude` in a Konsole window
  without a dashboard opens one in a new tab (DASH) next to it; `"dashboard_autostart": false` in
  `cockpit.json` turns that off.
- **Agenda tab**: with `"agenda_file"` in `cockpit.json` (e.g. `todos/AGENDA.md`), a tab before To-dos shows
  the day's focus, set each morning with `todo agenda <a>, <b>, …` (one `## YYYY-MM-DD` section per day, newest
  first); its items tick like to-dos. Until today's is set, the tab says so and shows the last one dimmed.
- **Jobs tab**: between To-dos and Commands, every regular job (`claude-jobs list --json`) with interval, last
  run, result and next run; failing ones first.
- **Web dashboard** (`cockpit-web`): the same as a page in the browser, served on `127.0.0.1:8765` by the
  user service `cockpit-web.service` (always on). Click a project to go to its Konsole tab (or open one),
  dismiss questions, tick to-dos; Tab/Shift+Tab switch tabs. With `"dashboard": "web"` in `cockpit.json`,
  starting `claude` opens the page instead of a DASH tab (unless one is open), and `dashboard` opens it too
  (`dashboard --tui` for the terminal one). Its JSON API (`/api/state`,
  `/api/open`, `/api/dismiss`, `/api/tick`, see `bin/cockpit-web`) is meant for other clients too.
- **Own window and taskbar icon**: with `"dashboard": "window"` in `cockpit.json`, the dashboard runs in a
  Konsole window of its own (`dashboard --window`; opened on session start if closed). `install.sh` adds two
  launchers to pin to the taskbar, each with its own icon, named after the workspace (`name` in `cockpit.json`,
  else "Claude"): **<name>** (`cockpit`, the sessions' window) and **<name> dashboard**. `"icons": {"cockpit": …, "dashboard": …}` (SVG or PNG,
  relative to the workspace) replaces their icons. With `"pin_launchers": true` in
  `cockpit.json`, every install run pins them to the first two slots of each Plasma task manager. Konsole's `--desktopfile` gives their windows their own Wayland app id, so they don't
  group under Konsole. Clicking a project raises the window holding its tab (KWin script, `lib/kwin-activate`).
- **Start** (`cockpit`): opens a Konsole window with the root session only (its last conversation resumed with
  `claude --resume` if it was open before) and the dashboard (web or window); project sessions start from the
  dashboard or via the root session. If the root session runs, its window comes to the front; `cockpit list` shows what it would open. With `"remote_control": true` in `cockpit.json`, the root
  session starts with Remote Control on, named after the workspace (reachable from the Claude apps).
- **Tabs**: each session is named after its folder (at most two levels deep, like the dashboard rows) and gets its tab title and colour automatically. Tabs
  are kept sorted: DASH, the root, projects A–Z, unnamed tabs last. Leaving `claude` closes its tab.
- **Status line**: model, context use, rate limits (▲ = used faster than the window passes), estimated
  cost, plus a big two-line logo of the project name in its tab
  colour.
- **Tab colours** (`tab-color`): `tab-color red` saves the current project's colour in `cockpit.json` and
  colours its tab now; sessions run it when the user names a colour.
- **Jobs** (`claude-jobs`): runs `<project>/jobs/<name>` scripts on their interval (systemd user timer).
- **Archive**: a project whose `Status:` line starts with `archived` is listed dimmed at the end of its category
  tab on the dashboard, and its jobs stop (rules C1).
- **Secrets** (`secret`): `secret set aligulac` stores an API key in the keyring (hidden prompt), `secret get`
  reads it. A shorter way to type `secret-tool store --label=… service …`. With `vault` set in `cockpit.json`
  and the 1Password CLI (`op`, app integration on), every secret is also kept in that 1Password vault:
  `secret push` copies the keyring into it, `secret pull` fills a new machine's keyring from it, and
  `secret get` falls back to it. Jobs still read the keyring, so they run without 1Password. With a 1Password **service account** limited to that vault (its token stored by
  `secret set op-service-account vault <vault>`, keyring only), `op` never asks to unlock 1Password.
- **Git before every answer**: each prompt first pulls the session's own repo (at most once a minute, a few
  seconds at most, fast-forward only, never over local changes) and tells Claude which files came in.
  `"after_pull"` in `cockpit.json` runs a command when the workspace repo moved (e.g. to clone new repos).
- **Other machines**: each machine publishes its running sessions to the branch `cockpit-presence/<host>` of
  the workspace repo (`lib/presence`); the dashboard shows a project open only elsewhere as `@<host>`, about a
  minute behind.
- **Updates**: every prompt pulls the cockpit in the background, so a change pushed from another machine
  arrives without doing anything; the next prompt says what came in.
- **Welcome and starter**: the root session's first start in a workspace with nothing but the cockpit shows
  a welcome; on the first message Claude explains the structure (`welcome.md`) and offers to deploy the
  starter: `cockpit-starter` (`--dry-run` lists what it would do) copies `starter/` into the workspace, an
  empty shell with no data, only the general instructions: root `CLAUDE.md` (operator tasks, folder map),
  `rules/workflow.md` (W1–W8: short replies, central to-dos and ideas, git, …), `todos/`, `ideas/`,
  `projects/`, `tmp/`, `jobs/git-sync`, `.gitignore`, a git repo and the to-do settings in `cockpit.json`.
  It never overwrites a file. Greeted once (`.cockpit/welcomed`).
- **Rules**: live in your workspace, in `<workspace>/rules/` (another folder: `"rules": "<folder>"` in
  `cockpit.json`). `install.sh` starts them from `rules/cockpit.md` (the cockpit conventions C1–C7) plus an
  empty `RULES.md` for your own; with `CLAUDE_RULES_REPO=<git url>` it offers to clone a shared ruleset
  instead. The workspace's `CLAUDE.md` loads them.

## Layout

| Path | What |
| --- | --- |
| `bin/dashboard` | the TUI (Python 3, no dependencies) |
| `bin/claude-jobs` | job runner |
| `bin/cockpit-web`, `web/index.html` | the web dashboard: local server (stdlib, reuses `bin/dashboard`'s `snapshot()`) and its page; `systemd/cockpit-web.service` |
| `bin/cockpit` | start command: opens the root session (resumed from `~/.cache/claude/open/`, written by `hooks/session-state.sh`) in a new Konsole window, opens the web dashboard |
| `lib/kwin-activate` | raises a window by pid via a one-off KWin script (Wayland) |
| `icons/` | launcher icons (`claude-cockpit`, `claude-dashboard`) |
| `bin/tab-color` | set a project's tab colour in `cockpit.json` and apply it to the tab |
| `bin/secret` | short form of `secret-tool`: `secret set/get/del <service> [attr value]…`, `push`/`pull` to 1Password |
| `hooks/session-name.sh` | SessionStart hook: session/tab name, tab colour, tab sorting, opens the dashboard tab if the window has none |
| `hooks/session-state.sh` | records each session's live state for the dashboard (`~/.cache/claude/sessions/`) and saves open questions apart from the session in `<workspace>/.cockpit/questions/` (versioned, so they move between machines) |
| `hooks/cockpit-pull.sh` | UserPromptSubmit hook: pulls the cockpit in the background (at most once a minute, fast-forward only, never over local changes), re-runs `install.sh` when the pull touched it, `systemd/` or `plugins/`, reports the update on the next prompt; log `~/.cache/claude/cockpit-pull.log` |
| `hooks/repo-pull.sh` | UserPromptSubmit hook: pulls the session's repo before Claude answers (see above); log `~/.cache/claude/repo-pull.log` |
| `lib/presence` | `push` / `fetch` / `show` / `usage`: this and the other machines' running sessions and token counts (branches `cockpit-presence/<host>`, one parentless commit each, force-pushed) |
| `hooks/sort-tabs.sh` | sorts the Konsole tabs of the current window |
| `hooks/statusline.sh` | Claude Code status line |
| `plugins/worklog/` | Claude Code mod: side pane with the project's status, the open `Your turn:` questions and a work log (or, with `cockpit.json` "panes", lines from files per project, "*" = default: e.g. rules, open points, chores, ideas); `/worklog` reopens it; `"panes": {"<project>": {"title", "file", "match"}}` in `cockpit.json` shows a file's matching lines (default `## ` headings) instead of the log |
| `shell/bashrc.sh` | sourced from `~/.bashrc`: dashboard-opened tabs start `claude`, the hook's DASH tab starts `dashboard`; `/exit` closes the tab |
| `lib/env.sh` | shared shell helpers: workspace location, session names, colours |
| `lib/konsole-app` | runs Konsole as its own app (a copy of the binary named after the launcher), so Plasma's taskbar shows its windows under that launcher, not under Konsole |
| `lib/konsole-color` | colours a Konsole tab: `setTabColor`, or on Konsole 26.08+ (no `setTabColor`) a generated profile `cockpit-RRGGBB` per colour in `~/.local/share/konsole/` (new colours show after a Konsole restart) |
| `systemd/` | `claude-jobs.service` / `.timer` |
| `cockpit.example.json` | template for the workspace's `cockpit.json` |
| `bin/cockpit-starter`, `starter/`, `welcome.md` | the starter structure, its deploy script, and the how-to the root session gets on its first start (`hooks/session-name.sh`) |
| `rules/cockpit.md` | the cockpit conventions (C1–C7), copied into a new workspace's rules by `install.sh` |

## Install

Needs Linux, KDE Konsole (D-Bus via `qdbus6`; Fedora: package `qt6-qttools`, whose `qdbus-qt6` the
installer links as `qdbus6`), Claude Code, `jq`, Python 3, systemd (user units) and
`secret-tool` (`libsecret-tools`).

1. Clone this repo into your workspace as `cockpit/`, e.g. `git clone … ~/claude/cockpit`.
2. Run `cockpit/install.sh`. It takes the parent folder as the workspace, or pass a path as the first
   argument. You can re-run it at any time. It:
   - links `bin/*` into `~/.local/bin`, the hooks into `~/.claude/hooks` and the status line to
     `~/.claude/statusline.sh`
   - adds whatever is missing to `~/.claude/settings.json` (backup in `settings.json.bak`): hooks, status line, and
     every folder in `plugins/` in `env.CLAUDE_CODE_PLUGIN_DIRS`, so each session loads them
   - installs and starts `claude-jobs.timer`
   - adds a line to `~/.bashrc` that loads `shell/bashrc.sh`
   - writes `<workspace>/cockpit.json` from the example if it doesn't exist
3. `install.sh` sets up the rules (your own from `rules/cockpit.md`, or a shared ruleset) and adds `@rules/RULES.md` to the workspace's root `CLAUDE.md`.
4. Optional: in `cockpit.json`, set tab colours (`colors`) and folders to skip (`hidden`).
5. Start `claude` (or `dashboard`) in a Konsole tab; the dashboard opens with it. Open projects by clicking them.
   In a fresh workspace, the first start greets you and offers the starter structure (`cockpit-starter`).

## Workspace config: `<workspace>/cockpit.json`

```json
{
  "name":      "claude",
  "vault":     "cockpit",
  "colors":    { "claude": "#7EC8F7", "work/reports": "#FFD600" },
  "hidden":    ["cockpit", "tmp"],
  "aliases":   { "old-name": "new-name" },
  "old_roots": ["~/old/workspace/location"],
  "depth":     2,
  "hidden_tabs": ["other"],
  "job_host":  "my-desktop"
}
```

- `name`: the root's session, tab and dashboard row name; default: the workspace folder's name.
- `vault`: a 1Password vault that `secret` mirrors every secret into (see Secrets); optional.
- `colors`: Konsole tab colour per folder path, relative to the workspace. The longest match wins, so a
  colour on a parent folder covers all its projects. The root is listed under its `name`.
- `hidden`: folders that the dashboard and the job runner skip.
- `depth` (default 2): how deep dashboard rows go. Deeper projects, e.g. worktrees in `group/repo/worktree`,
  count toward their ancestor at that depth.
- `hidden_tabs`: dashboard category tabs to leave out (e.g. `other`: the root and projects directly in the
  workspace); their running sessions still show in Active.
- `job_host`: with several machines on one workspace, the hostname that runs the jobs; others run only
  jobs marked `# machines: all`, and take over the rest if the job host's heartbeat
  (`.cockpit/job-host.json`) is older than a day. Unset: every machine runs every job.
- `aliases` / `old_roots`: renamed folders and earlier workspace locations, so that older transcripts
  still count toward the right project's token use.

The workspace location comes from `$CLAUDE_WORKSPACE`, or else from `~/.config/claude-cockpit/workspace`
(written by `install.sh`), or else defaults to `~/claude`.

## How it fits together

- **Live state**: the hooks `UserPromptSubmit`, `PostToolUse`, `Notification`, `Stop` and `SessionEnd`
  write `~/.cache/claude/sessions/<session id>.json`. A session counts as **question** when its last reply
  contains a `?` or `Your turn:` in its last 300 characters, or a permission dialog is open. It counts as
  **monitoring** when a wakeup, monitor or background task is pending. Sessions without a state file (started
  before the hooks were installed) fall back to Claude Code's own registry in `~/.claude/sessions/<pid>.json`
  (`busy`, `shell` = monitoring, `waiting` = question unless only a dialog the user opened).
- **Last action**: the last `tool_use` in the tail of a running session's transcript, worded as what was done,
  never prompt text.
- **Token use**: comes from the transcripts in `~/.claude/projects`, counting input + cache writes +
  output (cache reads are left out). The 5h / 7d windows line up with the subscription limits that the
  status line caches.
- **Konsole**: the cockpit only uses D-Bus calls that work while Konsole's "security sensitive D-Bus API" is
  off. That setting blocks sending commands into a tab, so a dashboard-opened tab starts `claude` through a
  marker file (`~/.cache/claude/autostart`) that `shell/bashrc.sh` reads.
