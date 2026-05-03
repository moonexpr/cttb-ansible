#!/bin/bash
# Update the wiki sitenotice (system-wide banner).
# Usage: wiki-sitenotice.sh /path/to/notice.txt
# Requires: source wiki-login.sh first
set -e

FILE="${1:-/tmp/wiki-sitenotice.txt}"

if [ -z "$WIKI_CSRF" ]; then
    echo "Not logged in. Run: source wiki-login.sh" >&2
    exit 1
fi

if [ ! -f "$FILE" ]; then
    echo "File not found: $FILE" >&2
    exit 1
fi

RESULT=$(curl -s -b "$WIKI_COOKIE" -X POST "$WIKI_API" \
  --data-urlencode "action=edit" \
  --data-urlencode "title=MediaWiki:Sitenotice" \
  --data-urlencode "token=$WIKI_CSRF" \
  --data-urlencode "summary=Update sitenotice" \
  --data-urlencode "format=json" \
  --data-urlencode "text@$FILE")

STATUS=$(echo "$RESULT" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('edit',{}).get('result','FAILED: '+str(d)))")
echo "Sitenotice: $STATUS"
