#!/bin/bash
# Login to wiki.cttb API and set up cookies for subsequent calls.
# Sources bot credentials from macOS Keychain.
# Usage: source wiki-login.sh
set -e
WIKI_API="http://10.11.1.34/w/api.php"
WIKI_COOKIE="/tmp/wiki-cookies"

BOT_USER=$(security find-generic-password -a "$USER" -s "WIKI_CTTB_BOT_USER" -w)
BOT_PASS=$(security find-generic-password -a "$USER" -s "WIKI_CTTB_BOT_PASSWD" -w)

rm -f "$WIKI_COOKIE"
TOKEN=$(curl -s -c "$WIKI_COOKIE" "$WIKI_API?action=query&meta=tokens&type=login&format=json" | python3 -c "import sys,json; print(json.load(sys.stdin)['query']['tokens']['logintoken'])")
LOGIN=$(curl -s -b "$WIKI_COOKIE" -c "$WIKI_COOKIE" -X POST "$WIKI_API" \
  --data-urlencode "action=login" \
  --data-urlencode "lgname=$BOT_USER" \
  --data-urlencode "lgpassword=$BOT_PASS" \
  --data-urlencode "lgtoken=$TOKEN" \
  --data-urlencode "format=json" | python3 -c "import sys,json; print(json.load(sys.stdin)['login']['result'])")

if [ "$LOGIN" != "Success" ]; then
    echo "Login failed: $LOGIN" >&2
    return 1 2>/dev/null || exit 1
fi

WIKI_CSRF=$(curl -s -b "$WIKI_COOKIE" "$WIKI_API?action=query&meta=tokens&format=json" | python3 -c "import sys,json; print(json.load(sys.stdin)['query']['tokens']['csrftoken'])")

export WIKI_API WIKI_COOKIE WIKI_CSRF
echo "Logged in. WIKI_API, WIKI_COOKIE, WIKI_CSRF exported."
