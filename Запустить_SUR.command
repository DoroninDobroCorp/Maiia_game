#!/bin/bash
DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$DIR"

export SUR_VIBEPROXY_URL="${SUR_VIBEPROXY_URL:-http://127.0.0.1:8318/v1}"
SUR_VIBEPROXY_KEY_FILE="${SUR_VIBEPROXY_KEY_FILE:-$HOME/.config/sur/vibeproxy.key}"
if [ -z "${SUR_VIBEPROXY_API_KEY:-}" ] && [ -r "$SUR_VIBEPROXY_KEY_FILE" ]; then
    IFS= read -r SUR_VIBEPROXY_API_KEY < "$SUR_VIBEPROXY_KEY_FILE"
    export SUR_VIBEPROXY_API_KEY
fi

GODOT_BIN="/Applications/Godot.app/Contents/MacOS/Godot"
if [ ! -x "$GODOT_BIN" ]; then
    GODOT_BIN="$(command -v godot 2>/dev/null)"
fi

if [ -x "$GODOT_BIN" ]; then
    "$GODOT_BIN" --path "$DIR"
else
    echo "Ошибка: Godot не найден в /Applications/Godot.app или в PATH."
    read -p "Нажмите Enter для выхода..."
fi
