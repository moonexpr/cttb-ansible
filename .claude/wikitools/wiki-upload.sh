#!/bin/bash
# Upload a file to wiki.cttb.
# Usage: wiki-upload.sh /path/to/file.png ["Upload comment"]
# Requires: source wiki-login.sh first
set -e

FILE="$1"
COMMENT="${2:-Uploaded via wiki-upload.sh}"

if [ -z "$FILE" ]; then
    echo "Usage: wiki-upload.sh /path/to/file.png [\"comment\"]" >&2
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

FILENAME=$(basename "$FILE")

RESULT=$(curl -s -b "$WIKI_COOKIE" -X POST "$WIKI_API" \
  -F "action=upload" \
  -F "filename=$FILENAME" \
  -F "comment=$COMMENT" \
  -F "token=$WIKI_CSRF" \
  -F "format=json" \
  -F "file=@$FILE" \
  -F "ignorewarnings=1")

STATUS=$(echo "$RESULT" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('upload',{}).get('result','FAILED: '+str(d)))")
echo "$FILENAME: $STATUS"
