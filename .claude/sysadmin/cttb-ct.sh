#!/usr/bin/env bash
# CTTB host / container shell helper.
#
# Wraps the SSH chains needed to reach common CTTB hosts and containers,
# so you can `cttb-ct shell wiki` instead of remembering the jump path.
#
# Direct SSH aliases (LXC=0): shell appends -t; exec appends cmd.
# LXC exec aliases  (LXC=1): CHAIN already includes `ssh -t host -- lxc exec ct --`;
#                             shell appends `bash`; exec appends cmd.
#
# srv-vm  (10.11.1.3)  — main LXC host: wiki-2404, ldap, buildworker, …
# srv-nas (10.11.1.5)  — secondary LXC host: pxe, debmirror, git, …
#
# Usage:
#   cttb-ct.sh list
#   cttb-ct.sh shell <alias>
#   cttb-ct.sh exec  <alias> <cmd...>
#   cttb-ct.sh push  <alias> <local> <remote>     # local -> remote
#   cttb-ct.sh pull  <alias> <remote> <local>     # remote -> local
#   cttb-ct.sh cp    <src> <dst>                  # scp-style; either side may
#                                                 # be <alias>:<path>
#
# To add a host: append one entry to DIRECT_SSH, VM_CTS, or NAS_CTS below.
# Entry format: alias:target:ip
#   target = ssh host (direct) or lxc container name (may differ from alias)
#   ip     = 10.11.x.x, or - if not applicable / unknown

set -euo pipefail

# ── Host tables ───────────────────────────────────────────────────────────────

DIRECT_SSH=(
    srv-gw:srv-gw:10.11.1.1
    srv-vm:srv-vm:10.11.1.3
    srv-nas:srv-nas:10.11.1.5
    cttb:cttb:-
    rui:rui-desktop2:-
)

VM_CTS=(          # LXC containers on srv-vm (10.11.1.3)
    wiki:wiki-2404:10.11.1.31
    dnsmasq:dnsmasq:10.11.1.19
    ub-adult:ub-adult:10.11.1.29
    ub-igdvs:ub-igdvs:10.11.1.28
    ldap:ldap:10.11.1.25
    mon:mon:10.11.1.26
    asterisk:asterisk:10.11.1.32
    jumpbox:jumpbox:10.11.1.33
    cups-cttb:cups-cttb:10.11.1.36
    cups-dvbs:cups-dvbs:10.11.1.37
    cups-dvgs:cups-dvgs:10.11.1.38
    sltp:sltp:10.11.1.39
    sltp-git:sltp-git:10.11.1.40
    drbu-sis:drbu-sis:10.11.1.41
    blogger:blogger:10.11.1.42
    buildworker:buildworker:-
    storehouse:storehouse:-
)

NAS_CTS=(         # LXC containers on srv-nas (10.11.1.5)
    fs:fs:10.11.1.18
    log:log:10.11.1.20
    git:git:10.11.1.21
    debmirror:debmirror:10.11.1.22
    pxe:pxe:-              # legacy 16.04-era container — STOPPED since 2026-05-12 cutover
    pxe24:pxe24:10.11.1.23 # live pxe.cttb (Ubuntu 24.04); re-IP'd from quarantine on cutover
    metrics:metrics:10.11.1.24
    koha:koha:10.11.1.27
)

# ── Derived alias list ────────────────────────────────────────────────────────
aliases=()
for _e in "${DIRECT_SSH[@]}" "${VM_CTS[@]}" "${NAS_CTS[@]}"; do
    aliases+=("${_e%%:*}")
done
unset _e

# ── Chain resolver ────────────────────────────────────────────────────────────
LXC=0

ssh_chain() {
    LXC=0
    local needle="$1" entry al rest target

    for entry in "${DIRECT_SSH[@]}"; do
        al="${entry%%:*}"; rest="${entry#*:}"; target="${rest%%:*}"
        [[ "$al" == "$needle" ]] || continue
        CHAIN=(ssh "$target"); return
    done

    for entry in "${VM_CTS[@]}"; do
        al="${entry%%:*}"; rest="${entry#*:}"; target="${rest%%:*}"
        [[ "$al" == "$needle" ]] || continue
        CHAIN=(ssh -t srv-vm -- lxc exec "$target" --); LXC=1; return
    done

    for entry in "${NAS_CTS[@]}"; do
        al="${entry%%:*}"; rest="${entry#*:}"; target="${rest%%:*}"
        [[ "$al" == "$needle" ]] || continue
        # lxc CLI on srv-nas is root-only; jc user can't read /etc/lxc config.
        CHAIN=(ssh -t srv-nas -- sudo lxc exec "$target" --); LXC=1; return
    done

    echo "unknown alias: $needle" >&2; return 1
}

# ── Table printer (for `list`) ────────────────────────────────────────────────
_print_table() {
    local A=16 I=14            # alias / ip column widths
    local W=$(( A + I + 3 ))   # total row width: 1 + A + 2 + I
    local heavy light row_fmt hdr_fmt
    heavy=$(printf '═%.0s' $(seq 1 $W))
    light=$(printf '─%.0s' $(seq 1 $W))
    row_fmt=" %-${A}s  %-${I}s"
    hdr_fmt=" %-$(( W - 1 ))s"

    local entry al ip

    printf '%s\n' "$heavy"
    # shellcheck disable=SC2059
    printf "${row_fmt}\n" "alias" "ip"
    printf '%s\n' "$light"

    # shellcheck disable=SC2059
    printf "${hdr_fmt}\n" "direct ssh"
    printf '%s\n' "$light"
    for entry in "${DIRECT_SSH[@]}"; do
        al="${entry%%:*}"; ip="${entry##*:}"
        printf "${row_fmt}\n" "$al" "$ip"
    done

    printf '%s\n' "$light"
    printf "${hdr_fmt}\n" "cttb compute hosts  (srv-vm)"
    printf '%s\n' "$light"
    for entry in "${VM_CTS[@]}"; do
        al="${entry%%:*}"; ip="${entry##*:}"
        printf "${row_fmt}\n" "$al" "$ip"
    done

    printf '%s\n' "$light"
    printf "${hdr_fmt}\n" "cttb network storage  (srv-nas)"
    printf '%s\n' "$light"
    for entry in "${NAS_CTS[@]}"; do
        al="${entry%%:*}"; ip="${entry##*:}"
        printf "${row_fmt}\n" "$al" "$ip"
    done

    printf '%s\n' "$heavy"
}

# ── File-transfer resolvers ───────────────────────────────────────────────────
# Classify an alias into one of {direct, srv-vm, srv-nas} and return its target
# (ssh host for direct; container name for LXC). Sets globals XFER_KIND and
# XFER_TARGET; returns 1 if the alias is unknown.

resolve_xfer() {
    local needle="$1" entry al rest target
    for entry in "${DIRECT_SSH[@]}"; do
        al="${entry%%:*}"; rest="${entry#*:}"; target="${rest%%:*}"
        [[ "$al" == "$needle" ]] || continue
        XFER_KIND=direct; XFER_TARGET="$target"; return
    done
    for entry in "${VM_CTS[@]}"; do
        al="${entry%%:*}"; rest="${entry#*:}"; target="${rest%%:*}"
        [[ "$al" == "$needle" ]] || continue
        XFER_KIND=srv-vm; XFER_TARGET="$target"; return
    done
    for entry in "${NAS_CTS[@]}"; do
        al="${entry%%:*}"; rest="${entry#*:}"; target="${rest%%:*}"
        [[ "$al" == "$needle" ]] || continue
        XFER_KIND=srv-nas; XFER_TARGET="$target"; return
    done
    echo "unknown alias: $needle" >&2; return 1
}

# Push <local> -> <alias>:<remote>. Stages via /tmp on the jump host for LXC.
# `lxc file push -r` rejects single files, so we only pass -r when the local
# path is actually a directory.
cttb_push() {
    local alias="${1:?need alias}" local_path="${2:?need local path}" remote="${3:?need remote path}"
    resolve_xfer "$alias"
    local base lxc_r=""
    base="$(basename "$local_path")"
    [[ -d "$local_path" ]] && lxc_r="-r"
    case "$XFER_KIND" in
        direct)
            scp -r "$local_path" "$XFER_TARGET:$remote"
            ;;
        srv-vm)
            scp -r "$local_path" "srv-vm:/tmp/$base"
            ssh srv-vm "lxc file push $lxc_r /tmp/$base $XFER_TARGET$remote && rm -rf /tmp/$base"
            ;;
        srv-nas)
            scp -r "$local_path" "srv-nas:/tmp/$base"
            ssh srv-nas "sudo lxc file push $lxc_r /tmp/$base $XFER_TARGET$remote && rm -rf /tmp/$base"
            ;;
    esac
}

# Pull <alias>:<remote> -> <local>. Stages via /tmp on the jump host for LXC.
# Detects whether the remote is a directory via `test -d` inside the container
# so we only pass -r to lxc file pull when appropriate.
cttb_pull() {
    local alias="${1:?need alias}" remote="${2:?need remote path}" local_path="${3:?need local path}"
    resolve_xfer "$alias"
    local base lxc_r=""
    base="$(basename "$remote")"
    case "$XFER_KIND" in
        direct)
            scp -r "$XFER_TARGET:$remote" "$local_path"
            ;;
        srv-vm)
            if ssh srv-vm "lxc exec $XFER_TARGET -- test -d $remote" 2>/dev/null; then lxc_r="-r"; fi
            ssh srv-vm "lxc file pull $lxc_r $XFER_TARGET$remote /tmp/$base"
            scp -r "srv-vm:/tmp/$base" "$local_path"
            ssh srv-vm "rm -rf /tmp/$base"
            ;;
        srv-nas)
            if ssh srv-nas "sudo lxc exec $XFER_TARGET -- test -d $remote" 2>/dev/null; then lxc_r="-r"; fi
            ssh srv-nas "sudo lxc file pull $lxc_r $XFER_TARGET$remote /tmp/$base"
            scp -r "srv-nas:/tmp/$base" "$local_path"
            ssh srv-nas "sudo rm -rf /tmp/$base"
            ;;
    esac
}

# scp-style cp: dispatches to push or pull based on which side has `<alias>:`.
cttb_cp() {
    local src="${1:?need source}" dst="${2:?need destination}"
    local src_remote=0 dst_remote=0
    [[ "$src" == *:* ]] && src_remote=1
    [[ "$dst" == *:* ]] && dst_remote=1
    if (( src_remote && dst_remote )); then
        echo "cross-host transfer is not supported; pull to local, then push" >&2
        return 2
    elif (( src_remote )); then
        cttb_pull "${src%%:*}" "${src#*:}" "$dst"
    elif (( dst_remote )); then
        cttb_push "${dst%%:*}" "$src" "${dst#*:}"
    else
        echo "no alias:path component; use cp <local> <alias>:<remote> or cp <alias>:<remote> <local>" >&2
        return 2
    fi
}

# ── Dispatch ──────────────────────────────────────────────────────────────────
cmd="${1:-}"
case "$cmd" in
    list)
        _print_table
        ;;
    shell)
        ssh_chain "${2:?need alias}"
        if [[ $LXC == 1 ]]; then
            exec "${CHAIN[@]}" bash
        else
            exec "${CHAIN[@]}" -t
        fi
        ;;
    exec)
        ssh_chain "${2:?need alias}"
        shift 2
        exec "${CHAIN[@]}" "$@"
        ;;
    push)
        shift; cttb_push "$@"
        ;;
    pull)
        shift; cttb_pull "$@"
        ;;
    cp)
        shift; cttb_cp "$@"
        ;;
    *)
        echo "Usage: $(basename "$0") list" >&2
        echo "       $(basename "$0") shell <alias>" >&2
        echo "       $(basename "$0") exec  <alias> <cmd...>" >&2
        echo "       $(basename "$0") push  <alias> <local> <remote>" >&2
        echo "       $(basename "$0") pull  <alias> <remote> <local>" >&2
        echo "       $(basename "$0") cp    <src> <dst>          # scp-style; alias:path either side" >&2
        echo "Aliases: ${aliases[*]}" >&2
        exit 2
        ;;
esac
