#!/bin/bash
# Edit a wiki page from a file.
# Usage: wiki-edit.sh "Page Title" /path/to/content.txt ["Edit summary"]
# Requires: source wiki-login.sh first
set -e

TITLE="$1"
FILE="$2"
SUMMARY="${3:-Automated edit via wiki-edit.sh}"

if [ -z "$TITLE" ] || [ -z "$FILE" ]; then
    echo "Usage: wiki-edit.sh \"Page Title\" /path/to/content.txt [\"summary\"]" >&2
    exit 1
fi

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
  --data-urlencode "title=$TITLE" \
  --data-urlencode "token=$WIKI_CSRF" \
  --data-urlencode "summary=$SUMMARY" \
  --data-urlencode "format=json" \
  --data-urlencode "text@$FILE")

STATUS=$(echo "$RESULT" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('edit',{}).get('result','FAILED: '+str(d)))")
echo "$TITLE: $STATUS"
