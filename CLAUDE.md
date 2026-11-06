# Claude cockpit

Status: dashboard, tabs, hooks, job runner (needs/takeover), per-session models; own session since 2026-11-03

## Open
- Live state (`.cockpit/questions`, job-host heartbeat) still in the workspace repo: move to presence branches
- Konsole `--desktopfile` no longer sets the app id: KWin rules (install.sh) cover it
- Sessions on another machine: left click in a real Konsole untested; messaging between machines only via Remote Control, unverified
- A remote session shows in presence only after its first prompt, so the never-twice guard misses it until then

## Setup

The generic cockpit for running Claude Code sessions per project in Konsole tabs: the dashboard TUI, the hooks,
the status line and the job runner. The rules the sessions follow are a separate repo (`<workspace>/rules/`,
installed by `install.sh`). What it does, its layout and how to
install it are in `README.md`.

- **Keep it generic.** The repo is public and colleagues at work use it too. Nothing about one person, machine or workspace
  goes in here, no names, paths or colours: those belong in the workspace's `cockpit.json` and `CLAUDE.md`.
- It's worked on from its own session in this folder (rules C5); other sessions send their requests here (C7).
- Shell scripts find the workspace through `lib/env.sh`; the two Python scripts each carry a copy of `workspace()`
  (`python3 -I` can't import from the script's folder).
- Every workspace pulls this repo on each prompt (`hooks/cockpit-pull.sh`), so push finished work: what is
  pushed reaches every machine; uncommitted changes block the pull there until they are committed.
- After changing `install.sh`, `systemd/` or the hook list, re-run `./install.sh`. Hooks, `bin/` and the status
  line are symlinked, so other edits take effect immediately.
- Test without side effects: `dashboard --once`, `claude-jobs list`, pipe `{"cwd": "…"}` into a hook.
