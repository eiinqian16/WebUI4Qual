#!/bin/sh

read -r POST_DATA

LANG_CODE=$(echo "$POST_DATA" | sed -n 's/.*lang=\([a-zA-Z_-]*\).*/\1/p')

case "$LANG_CODE" in
    en|ms|zh)
        uci set system.@system[0].webui_lang="$LANG_CODE"
        uci commit system

        echo "Content-Type: application/json"
        echo ""
        printf '{"success":"true","lang":"%s"}\n' "$LANG_CODE"
        ;;
    *)
        echo "Content-Type: application/json"
        echo ""
        echo '{"success":"false","error":"Unsupported or missing lang value"}'
        exit 1
        ;;
esac
