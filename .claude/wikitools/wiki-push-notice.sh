#!/bin/bash
set -e
WIKI_API="http://10.11.1.34/w/api.php"
COOKIE="/tmp/wiki-cookies"
BOT_USER=$(security find-generic-password -a "$USER" -s "WIKI_CTTB_BOT_USER" -w)
BOT_PASS=$(security find-generic-password -a "$USER" -s "WIKI_CTTB_BOT_PASSWD" -w)
rm -f "$COOKIE"
TOKEN=$(curl -s -c "$COOKIE" "$WIKI_API?action=query&meta=tokens&type=login&format=json" | python3 -c "import sys,json; print(json.load(sys.stdin)['query']['tokens']['logintoken'])")
curl -s -b "$COOKIE" -c "$COOKIE" -X POST "$WIKI_API" \
  --data-urlencode "action=login" --data-urlencode "lgname=$BOT_USER" \
  --data-urlencode "lgpassword=$BOT_PASS" --data-urlencode "lgtoken=$TOKEN" \
  --data-urlencode "format=json" > /dev/null
CSRF=$(curl -s -b "$COOKIE" "$WIKI_API?action=query&meta=tokens&format=json" | python3 -c "import sys,json; print(json.load(sys.stdin)['query']['tokens']['csrftoken'])")

edit_page() {
    RESULT=$(curl -s -b "$COOKIE" -X POST "$WIKI_API" \
      --data-urlencode "action=edit" --data-urlencode "title=$1" \
      --data-urlencode "token=$CSRF" --data-urlencode "summary=$3" \
      --data-urlencode "format=json" --data-urlencode "text@$2")
    echo "$1: $(echo "$RESULT" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('edit',{}).get('result','FAILED'))")"
}

edit_page "MediaWiki:Sitenotice" "/tmp/wiki-sitenotice.txt" "Update sitenotice"
edit_page "MediaWiki:Common.js" "/tmp/wiki-commonjs.txt" "Add dismissable sitenotice JS"
