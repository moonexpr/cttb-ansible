#!/usr/bin/env bash
# Validate the Sudhanix welcome-dismissal LDAP plumbing.
#
# Modes:
#   ./validate.sh                  summary report (schema, ACL, dismissed-user count)
#   ./validate.sh --watch          live watch for new dismissals (Ctrl-C to stop)
#   ./validate.sh --user UID       full report for one user
#   ./validate.sh --reset UID      clear flag + sudhanixUser class on UID (prompts for that user's password)
#
# Connects via StartTLS on 389. Set CTTB_LDAP_HOST / CTTB_LDAP_BASE to override.
# Cert hostname mismatch is tolerated (LDAPTLS_REQCERT=never) — fine for diagnostics.

set -u

LDAP_HOST="${CTTB_LDAP_HOST:-ldap.cttb}"
LDAP_URI="ldap://${LDAP_HOST}"
BASE="${CTTB_LDAP_BASE:-dc=cttb}"
PEOPLE_OU="ou=People,${BASE}"
ATTR="sudhanixWelcomeDismissed"
OC="sudhanixUser"

export LDAPTLS_REQCERT=never

bold()  { printf '\033[1m%s\033[0m\n' "$*"; }
green() { printf '\033[32m%s\033[0m\n' "$*"; }
red()   { printf '\033[31m%s\033[0m\n' "$*"; }
gray()  { printf '\033[90m%s\033[0m\n' "$*"; }

ldsearch() {
  ldapsearch -ZZ -x -LLL -H "$LDAP_URI" "$@" 2>/dev/null
}

check_schema() {
  bold "Schema"
  local out
  out="$(ldsearch -b cn=subschema -s base attributeTypes 2>/dev/null | grep -i "$ATTR" || true)"
  if [[ -n "$out" ]]; then
    green "  ✓ ${ATTR} attributeType registered"
  else
    red   "  ✗ ${ATTR} NOT in cn=subschema — run roles/ldap-schema-sudhanix"
    return 1
  fi
  out="$(ldsearch -b cn=subschema -s base objectClasses 2>/dev/null | grep -i "${OC}" || true)"
  if [[ -n "$out" ]]; then
    green "  ✓ ${OC} objectClass registered"
  else
    red   "  ✗ ${OC} objectClass NOT registered"
    return 1
  fi
}

check_acl() {
  bold "ACL"
  gray "  (cn=config requires SASL EXTERNAL on the server itself; skipping remote probe)"
  gray "  Verify on ldap-srv with:"
  gray "    sudo ldapsearch -Y EXTERNAL -H ldapi:/// -LLL \\"
  gray "      -b 'olcDatabase={1}mdb,cn=config' olcAccess | grep -i ${ATTR}"
}

count_dismissed() {
  bold "Dismissals"
  local count
  count="$(ldsearch -b "$PEOPLE_OU" "(${ATTR}=TRUE)" dn 2>/dev/null | grep -c '^dn: ' || true)"
  echo "  Users with ${ATTR}=TRUE: ${count}"
  if (( count > 0 )); then
    gray  "  Most recent 5:"
    ldsearch -b "$PEOPLE_OU" "(${ATTR}=TRUE)" uid modifyTimestamp \
      | awk '/^uid:/{u=$2} /^modifyTimestamp:/{print "    " $2 "  " u}' \
      | sort -r | head -5
  fi
}

per_user_report() {
  local uid="$1"
  local dn="uid=${uid},${PEOPLE_OU}"
  bold "User: ${dn}"
  local out
  out="$(ldsearch -b "$dn" -s base '(objectClass=*)' objectClass "$ATTR" modifyTimestamp 2>&1)"
  if [[ -z "$out" ]]; then
    red "  ✗ entry not found or not readable"
    return 1
  fi
  echo "$out" | sed 's/^/  /'
  echo
  if echo "$out" | grep -q "^${ATTR}: TRUE"; then
    green "  → DISMISSED"
  elif echo "$out" | grep -q "objectClass: ${OC}"; then
    red   "  → has ${OC} class but flag not TRUE — partial / stale state"
  else
    gray  "  → not dismissed (clean state)"
  fi
}

reset_user() {
  local uid="$1"
  local dn="uid=${uid},${PEOPLE_OU}"
  bold "Reset ${dn}"
  echo "  This will:"
  echo "    1. delete ${ATTR}"
  echo "    2. remove objectClass: ${OC}"
  echo "  Bind DN: ${dn}"
  echo "  Enter that user's LDAP password when prompted."
  echo
  ldapmodify -x -D "$dn" -W -ZZ -H "$LDAP_URI" <<EOF
dn: ${dn}
changetype: modify
delete: ${ATTR}
-
delete: objectClass
objectClass: ${OC}
EOF
}

watch_mode() {
  bold "Watching ${LDAP_URI} for new dismissals (Ctrl-C to stop)"
  local prev=""
  while true; do
    local cur
    cur="$(ldsearch -b "$PEOPLE_OU" "(${ATTR}=TRUE)" uid modifyTimestamp \
      | awk '/^uid:/{u=$2} /^modifyTimestamp:/{print $2 " " u}' | sort)"
    if [[ "$cur" != "$prev" ]]; then
      clear
      bold "$(date)  —  $(echo "$cur" | grep -c . ) dismissed"
      echo "$cur"
      prev="$cur"
    fi
    sleep 2
  done
}

main() {
  case "${1:-}" in
    "")
      check_schema || exit 1
      echo
      check_acl
      echo
      count_dismissed
      echo
      gray "Tip: ./validate.sh --user <uid>     for one student's state"
      gray "     ./validate.sh --watch          live monitor"
      ;;
    --watch)
      watch_mode
      ;;
    --user)
      [[ -n "${2:-}" ]] || { red "usage: $0 --user <uid>"; exit 2; }
      per_user_report "$2"
      ;;
    --reset)
      [[ -n "${2:-}" ]] || { red "usage: $0 --reset <uid>"; exit 2; }
      reset_user "$2"
      ;;
    -h|--help)
      sed -n '2,11p' "$0" | sed 's/^# \{0,1\}//'
      ;;
    *)
      red "unknown arg: $1"
      exit 2
      ;;
  esac
}

main "$@"
