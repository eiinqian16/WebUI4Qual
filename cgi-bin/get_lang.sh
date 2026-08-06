#!/bin/sh

echo "Content-Type: application/json"
echo ""

LANG_CODE=$(uci -q get system.@system[0].webui_lang 2>/dev/null)

if [ -z "$LANG_CODE" ]; then
    LANG_CODE="en"
fi

printf '{"lang":"%s"}\n' "$LANG_CODE"
