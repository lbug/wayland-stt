#!/usr/bin/env bash
# Symlinks stt-toggle into ~/.local/bin and binds it to a GNOME shortcut (default F9).
# Usage: ./install.sh [KEY]      e.g. ./install.sh '<Super>h'
#        ./install.sh --uninstall
set -euo pipefail
KEY=${1:-F9}
BIN=$HOME/.local/bin/stt-toggle
CFG=${XDG_CONFIG_HOME:-$HOME/.config}/wayland-stt/config
SCHEMA=org.gnome.settings-daemon.plugins.media-keys
PATH_=/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/wayland-stt/
list=$(gsettings get $SCHEMA custom-keybindings)
list=${list#@as }; list=${list//\'$PATH_\'/}; list=$(sed "s/, *,/,/g;s/\[, */[/;s/, *\]/]/" <<<"$list")

if [[ $KEY == --uninstall ]]; then
  gsettings set $SCHEMA custom-keybindings "$list"
  gsettings reset-recursively $SCHEMA.custom-keybinding:$PATH_
  rm -f "$BIN"; echo "Removed (config kept at $CFG)"; exit 0
fi

for dep in pw-record curl jq notify-send wl-copy; do
  command -v $dep >/dev/null || { echo "Missing: $dep  (sudo apt install wl-clipboard jq curl pipewire-bin libnotify-bin)"; exit 1; }
done

# Symlink so edits in the repo take effect on the next key press; rerun only to change the key.
mkdir -p "$(dirname "$BIN")"
ln -sfn "$(realpath "$(dirname "$0")/stt-toggle")" "$BIN"
git -C "$(dirname "$0")" config core.hooksPath .githooks 2>/dev/null || true
if [[ ! -e $CFG ]]; then
  install -Dm600 "$(dirname "$0")/config.example" "$CFG"
  echo "Created $CFG — put your OpenRouter key there."
fi

[[ $list == "[]" ]] && list="['$PATH_']" || list="${list%]}, '$PATH_']"
gsettings set $SCHEMA custom-keybindings "$list"
gsettings set $SCHEMA.custom-keybinding:$PATH_ name 'Speech-to-Text'
gsettings set $SCHEMA.custom-keybinding:$PATH_ command "$BIN"
gsettings set $SCHEMA.custom-keybinding:$PATH_ binding "$KEY"
echo "Bound $KEY -> $BIN"
