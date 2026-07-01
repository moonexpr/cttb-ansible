#!/usr/bin/env bash
# register-device.sh — helper for the /register-device skill.
#
# Moves one device out of the block13 quarantine pool by appending a single
# dhcp-host line to /etc/dnsmasq-hosts/<category> on lxc-dnsmasq, mirroring
# the same line into the local config clone, SIGHUPing dnsmasq, and
# verifying. Called once per invocation by the skill orchestrator. Never
# regenerated at runtime — captured logic, lives in the skill folder.
#
# See ../SKILL.md for the surrounding procedure and rationale.

set -euo pipefail

# --- config -----------------------------------------------------------------

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# .claude/skills/register-device/scripts/  →  .claude/sysadmin/cttb-ct.sh
CTTB_CT="$(cd "$SCRIPT_DIR/../../../sysadmin" && pwd)/cttb-ct.sh"
DNSMASQ_CLONE="${DNSMASQ_CLONE:-$HOME/Garden/external/dnsmasq}"

ALLOWED_CATEGORIES="adult visitors drbu servers switches voip waps restricted testlab temp"
DEFAULT_EXPIRES_LONGTERM="2046-12-31"
DEFAULT_VISITOR_DAYS=90

# --- CLI --------------------------------------------------------------------

MAC=""; CATEGORY="adult"; HOSTNAME=""; OWNER=""; TYPE=""; MODEL=""
EXPIRES=""; COMMENT=""; REGISTRAR=""; IP=""; DRY_RUN=0

usage() {
  cat <<'USAGE'
Usage: register-device.sh
  --mac <aa:bb:cc:dd:ee:ff>      (required)
  --hostname <name>              (required; collision-checked)
  --owner   "<full name>"        (required)
  --type    phone|laptop|desktop|tablet|other   (required)
  --model   "<free text>"        (required)
  [--category adult|visitors|drbu|servers|switches|voip|waps|restricted|testlab|temp]
                                 (default: adult)
  [--expires YYYY-MM-DD]         (default: 2046-12-31 for long-term,
                                  today+90d for visitors/temp)
  [--comment "<free text>"]
  [--registrar <user>]           (default: $(whoami))
  [--ip <addr>]                  (required for non adult/visitors;
                                  auto-allocated via next-ip.py otherwise)
  [--dry-run]                    (compose+probe only, no writes)
USAGE
}

while [ $# -gt 0 ]; do
  case "$1" in
    --mac)       MAC="$2"; shift 2 ;;
    --hostname)  HOSTNAME="$2"; shift 2 ;;
    --owner)     OWNER="$2"; shift 2 ;;
    --type)      TYPE="$2"; shift 2 ;;
    --model)     MODEL="$2"; shift 2 ;;
    --category)  CATEGORY="$2"; shift 2 ;;
    --expires)   EXPIRES="$2"; shift 2 ;;
    --comment)   COMMENT="$2"; shift 2 ;;
    --registrar) REGISTRAR="$2"; shift 2 ;;
    --ip)        IP="$2"; shift 2 ;;
    --dry-run)   DRY_RUN=1; shift ;;
    -h|--help)   usage; exit 0 ;;
    *)           echo "ERROR: unknown arg: $1" >&2; usage >&2; exit 64 ;;
  esac
done

# --- validation -------------------------------------------------------------

die()  { echo "ERROR: $*" >&2; exit "${2:-1}"; }
warn() { echo "WARN:  $*" >&2; }

[ -n "$MAC" ]      || die "--mac required"      64
[ -n "$HOSTNAME" ] || die "--hostname required" 64
[ -n "$OWNER" ]    || die "--owner required"    64
[ -n "$TYPE" ]     || die "--type required"     64
[ -n "$MODEL" ]    || die "--model required"    64
[ -n "$REGISTRAR" ] || REGISTRAR="$(whoami)"

# Normalize + validate MAC (lowercase, colon-separated)
MAC="$(printf '%s' "$MAC" | tr 'A-Z' 'a-z')"
printf '%s' "$MAC" | grep -qE '^[0-9a-f]{2}(:[0-9a-f]{2}){5}$' \
  || die "bad MAC format: '$MAC' (expected aa:bb:cc:dd:ee:ff)" 64

# Validate hostname (DNS-safe label, no whitespace)
printf '%s' "$HOSTNAME" | grep -qE '^[a-z0-9][a-z0-9-]{0,62}$' \
  || die "bad hostname '$HOSTNAME' (lowercase, alnum/dash, 1-63 chars, no leading dash)" 64

# Validate category
case " $ALLOWED_CATEGORIES " in
  *" $CATEGORY "*) : ;;
  *) die "unknown category '$CATEGORY' (allowed: $ALLOWED_CATEGORIES)" 64 ;;
esac

# Validate type
case "$TYPE" in
  phone|laptop|desktop|tablet|other) : ;;
  *) die "bad --type '$TYPE' (phone|laptop|desktop|tablet|other)" 64 ;;
esac

# Default expires by category
if [ -z "$EXPIRES" ]; then
  case "$CATEGORY" in
    visitors|temp)
      # macOS (BSD date) and Linux (GNU date) differ
      EXPIRES="$(date -v+${DEFAULT_VISITOR_DAYS}d "+%Y-%m-%d" 2>/dev/null \
                 || date -d "+${DEFAULT_VISITOR_DAYS} days" "+%Y-%m-%d")"
      ;;
    *)
      EXPIRES="$DEFAULT_EXPIRES_LONGTERM"
      ;;
  esac
fi
printf '%s' "$EXPIRES" | grep -qE '^[0-9]{4}-[0-9]{2}-[0-9]{2}$' \
  || die "bad --expires '$EXPIRES' (expected YYYY-MM-DD)" 64

# Tooling reachable?
[ -x "$CTTB_CT" ] || die "cttb-ct.sh not found or not exec at $CTTB_CT" 65

# --- box probe (read-only, single round trip) -------------------------------
# Ship a small probe via base64 so quoting/TAB issues never leak between
# this script and the remote shell. Returns key=value lines.

PROBE=$(cat <<PROBE_EOF
set -e
MAC="$MAC"
HN="$HOSTNAME"
DUP=\$(grep -inE "^\${MAC}," /etc/dnsmasq-hosts/* 2>/dev/null | head -1 || true)
HC=\$(awk -F, -v h="\$HN" 'NF>=3 { n=\$3; sub(/[[:space:]#,].*/, "", n); if (n==h) print FILENAME ":" NR ": " \$0 }' /etc/dnsmasq-hosts/* 2>/dev/null | head -1 || true)
DATE=\$(date "+%a %b %_d %H:%M:%S %Y")
SVC=\$(systemctl is-active dnsmasq 2>/dev/null || echo unknown)
printf 'DUP::%s\n'  "\$DUP"
printf 'HC::%s\n'   "\$HC"
printf 'DATE::%s\n' "\$DATE"
printf 'SVC::%s\n'  "\$SVC"
PROBE_EOF
)
PROBE_B64="$(printf '%s' "$PROBE" | base64 | tr -d '\n')"

PROBE_OUT="$("$CTTB_CT" exec dnsmasq "echo $PROBE_B64 | base64 -d | sh" 2>/dev/null \
  | grep -E '^(DUP|HC|DATE|SVC)::' || true)"

[ -n "$PROBE_OUT" ] || die "box probe returned nothing (is lxc-dnsmasq reachable?)" 65

# Parse probe output
DUP_LINE="$(printf '%s\n' "$PROBE_OUT" | sed -n 's/^DUP:://p')"
HC_LINE="$( printf '%s\n' "$PROBE_OUT" | sed -n 's/^HC:://p')"
BOX_DATE="$(printf '%s\n' "$PROBE_OUT" | sed -n 's/^DATE:://p')"
SVC_STATE="$(printf '%s\n' "$PROBE_OUT" | sed -n 's/^SVC:://p')"

[ -n "$BOX_DATE" ] || die "box probe didn't return DATE (unexpected; aborting)" 65
[ "$SVC_STATE" = "active" ] || warn "dnsmasq.service state on box is '$SVC_STATE', not 'active'"

if [ -n "$DUP_LINE" ]; then
  echo "ERROR: MAC $MAC is already registered on the box:" >&2
  echo "  $DUP_LINE" >&2
  echo "Refusing to write a duplicate dhcp-host (dnsmasq treats duplicates as" >&2
  echo "last-wins, which would corrupt the existing binding). If this is a" >&2
  echo "paste-buffer carryover, re-paste the intended MAC." >&2
  exit 70
fi

if [ -n "$HC_LINE" ]; then
  echo "ERROR: hostname '$HOSTNAME' is already in use on the box:" >&2
  echo "  $HC_LINE" >&2
  echo "Pick a different hostname (e.g. ${HOSTNAME}-2) and re-run." >&2
  exit 71
fi

# --- IP allocation ----------------------------------------------------------

if [ -z "$IP" ]; then
  case "$CATEGORY" in
    adult)
      IP="$("$CTTB_CT" exec dnsmasq "cd /home/administrator/dnsmasq.git && python next-ip.py resident" 2>&1 \
            | awk -F': ' '/next free IP/ {print $2}' | tr -d '\r\n ')"
      ;;
    visitors)
      IP="$("$CTTB_CT" exec dnsmasq "cd /home/administrator/dnsmasq.git && python next-ip.py visitor" 2>&1 \
            | awk -F': ' '/next free IP/ {print $2}' | tr -d '\r\n ')"
      ;;
    *)
      die "--ip is required for category '$CATEGORY' (next-ip.py only covers adult/visitors)" 64
      ;;
  esac
  printf '%s' "$IP" | grep -qE '^10\.11\.[0-9]{1,3}\.[0-9]{1,3}$' \
    || die "next-ip.py did not return a valid 10.11.x.y IP (got: '$IP')" 72
fi

# --- compose the entry line (TAB before #) ----------------------------------

# Use a literal TAB; portable across BSD/GNU printf with %b.
TAB="$(printf '\t')"
COMMENT_FIELD="${COMMENT:-.}"
LINE="${MAC},${IP},${HOSTNAME}${TAB}# Registered on: ${BOX_DATE}. Owner: ${OWNER}, type: ${TYPE}, model: ${MODEL}, expiration date: ${EXPIRES}, registrar: ${REGISTRAR}, comment: ${COMMENT_FIELD}."

echo "==="
echo "category:   ${CATEGORY}"
echo "ip:         ${IP}"
echo "line:       ${LINE}"
echo "==="

if [ "$DRY_RUN" = "1" ]; then
  echo "DRY-RUN — no writes."
  exit 0
fi

# --- write to live box, then mirror to local clone --------------------------
# base64-envelope the line so the TAB and any shell-meta survive the
# ssh -t -- lxc exec -- chain unmolested.

LINE_B64="$(printf '%s\n' "$LINE" | base64 | tr -d '\n')"
APPEND_FILE="/etc/dnsmasq-hosts/${CATEGORY}"
"$CTTB_CT" exec dnsmasq "echo $LINE_B64 | base64 -d >> $APPEND_FILE" >/dev/null \
  || die "append to $APPEND_FILE on box failed" 73

# Mirror to local clone (no auto-commit).
LOCAL_FILE="${DNSMASQ_CLONE}/dnsmasq-hosts/${CATEGORY}"
if [ -f "$LOCAL_FILE" ]; then
  printf '%s\n' "$LINE" >> "$LOCAL_FILE"
  MIRROR_STATUS="OK: $LOCAL_FILE"
else
  MIRROR_STATUS="SKIPPED: $LOCAL_FILE does not exist (clone missing?); box write still applied"
  warn "$MIRROR_STATUS"
fi

# --- SIGHUP + verify --------------------------------------------------------

"$CTTB_CT" exec dnsmasq "kill -HUP \$(cat /var/run/dnsmasq/dnsmasq.pid 2>/dev/null || pgrep -x dnsmasq | head -1)" >/dev/null \
  || warn "SIGHUP to dnsmasq failed; dhcp-hostsdir reads on file change anyway"

sleep 1

VERIFY=$(cat <<VERIFY_EOF
set -e
MAC="$MAC"
CAT="$CATEGORY"
STATE=\$(systemctl is-active dnsmasq 2>/dev/null || echo unknown)
HIT=\$(grep -n "^\${MAC}," /etc/dnsmasq-hosts/\${CAT} 2>/dev/null | head -1 || true)
JRN=\$(journalctl -u dnsmasq --since "30 seconds ago" --no-pager 2>/dev/null | grep -E "read /etc/dnsmasq-hosts/\${CAT}" | tail -1 || true)
printf 'STATE::%s\n' "\$STATE"
printf 'HIT::%s\n'   "\$HIT"
printf 'JRN::%s\n'   "\$JRN"
VERIFY_EOF
)
VERIFY_B64="$(printf '%s' "$VERIFY" | base64 | tr -d '\n')"
VERIFY_OUT="$("$CTTB_CT" exec dnsmasq "echo $VERIFY_B64 | base64 -d | sh" 2>/dev/null \
  | grep -E '^(STATE|HIT|JRN)::' || true)"

V_STATE="$(printf '%s\n' "$VERIFY_OUT" | sed -n 's/^STATE:://p')"
V_HIT="$(  printf '%s\n' "$VERIFY_OUT" | sed -n 's/^HIT:://p')"
V_JRN="$(  printf '%s\n' "$VERIFY_OUT" | sed -n 's/^JRN:://p')"

echo
echo "=== VERIFY ==="
echo "  dnsmasq state:     ${V_STATE:-?}"
echo "  entry in file:     ${V_HIT:-(missing — re-check)}"
echo "  journal re-read:   ${V_JRN:-(none — dnsmasq may have missed HUP)}"
echo "  local-clone mirror: ${MIRROR_STATUS}"
echo
echo "DONE. Tell the user: toggle Wi-Fi off and on on the device. It will"
echo "release its block13 lease and DHCP onto ${IP} (DNS=10.11.1.29,"
echo "route=10.11.1.1). The new lease will appear in"
echo "/var/lib/misc/dnsmasq.leases within seconds."
