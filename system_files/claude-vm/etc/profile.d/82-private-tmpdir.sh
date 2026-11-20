# shellcheck shell=sh
# Login shells of human accounts (caspertdk over SSH) get a per-user scratch directory instead of the shared /tmp.
# The agent accounts (claude, claude-rc-personal) already have a private /tmp through PrivateTmp=yes on their units.
# Only tools that honour $TMPDIR benefit; anything that hardcodes /tmp still uses the shared one.
case "$(id -un)" in
claude | claude-rc-personal) ;;
*)
    # pam_systemd sets XDG_RUNTIME_DIR to /run/user/<uid> (a per-user tmpfs, mode 0700) for SSH logins.
    if [ -n "${XDG_RUNTIME_DIR:-}" ] && [ -d "$XDG_RUNTIME_DIR" ] && [ -w "$XDG_RUNTIME_DIR" ]; then
        export TMPDIR="$XDG_RUNTIME_DIR"
    fi
    ;;
esac
