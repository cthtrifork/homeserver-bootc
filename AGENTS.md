# Notes for coding agents

Learnings about running Claude Code on the `claude-vm` image built from this repo. The VM-level policy itself lives in
`system_files/claude-vm/etc/claude-code/` (`CLAUDE.md` and `managed-settings.json`); this file explains the practical
consequences.

## Why you may still be prompted

`managed-settings.json` sets `permissions.defaultMode` to `bypassPermissions`, allows `Bash`, and enables
`sandbox.autoAllowBashIfSandboxed`. That is **only the default**. The mode a session is started with (CLI flag, web/app
mode selector, stored preference) overrides it. Check the session info: if `Permissions:` says `Auto` (or anything other
than bypass), the prompts are expected.

- Start sessions with `--permission-mode bypassPermissions`, or pick that mode in the client (Shift+Tab cycles modes).
- Managed settings are read at session start. A session that predates an image/settings change keeps the old policy.
- Enterprise org policy may disable bypass mode, in which case `defaultMode` cannot take effect.

In Auto mode, allow rules (including the bare `Bash` rule) and `autoAllowBashIfSandboxed` do **not** override the
checks below.

## Bash shapes that prompt (avoid them)

- Command substitution `$(...)` and backticks. Prompt text: "A nested command in this command can't be checked before
  it runs". Run the inner command in its own call and paste the literal result into the next command.
- `${...}` expansions (`${#VAR}`, `${VAR:0:3}`). Plain `$HOME` is fine.
- Shell loops over a variable set at run time (`for f in a b; do cmd $f; done`). Write each command out, or put the
  loop in a script file in the scratchpad and run the file.
- `cd <dir outside the working dir> && ...`. Use absolute paths, or `git -C <dir>`.
- Heredocs piped into an interpreter (`python3 - <<EOF`). Write a script file and run it.
- Commands not on an allow list, even when plain (e.g. `go env GOMODCACHE`).
- Reads outside `~/workspace` via Bash (e.g. `grep` in the Go module cache). The Go module cache is
  `/var/home/claude/go/pkg/mod`; use that literal path rather than asking `go env`.

Prefer the Read/Grep/Glob tools over Bash for reading and searching files when they are available in the session.

## Network and filesystem reminders

- Writes are limited to `~/workspace`, `~/.npm-global`, `~/.npm`, `~/.local`, `~/.cache` and `~/go`.
- Only hosts in `build_files/claude-vm/egress-allowlist.txt` are reachable. If a command fails with a network error,
  report the host instead of retrying; adding a host means editing that file and rebuilding the image.
- `podman` is excluded from the sandbox and always asks for approval.
