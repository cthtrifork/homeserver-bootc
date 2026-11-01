# For the claude user only: npm -g, pip --user and go install write under $HOME because /usr is read-only.
if [ "$(id -un)" = "claude" ]; then
    export NPM_CONFIG_PREFIX="$HOME/.npm-global"
    export XDG_RUNTIME_DIR="/run/user/$(id -u)"
    case ":$PATH:" in *":$NPM_CONFIG_PREFIX/bin:"*) ;; *) export PATH="$NPM_CONFIG_PREFIX/bin:$HOME/.local/bin:$HOME/go/bin:$PATH" ;; esac
fi
