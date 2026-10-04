# shellcheck shell=sh
# AgentUX: make the per-user tools installed by first-login (agent CLIs and
# ACP adapters in ~/.local/bin, mise-managed tools via shims) available to
# login shells.
for _agentux_dir in "${XDG_DATA_HOME:-$HOME/.local/share}/mise/shims" "$HOME/.local/bin"; do
    case ":$PATH:" in
        *":$_agentux_dir:"*) ;;
        *) PATH="$_agentux_dir:$PATH" ;;
    esac
done
unset _agentux_dir
export PATH
