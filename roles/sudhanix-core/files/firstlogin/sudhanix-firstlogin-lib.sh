#!/bin/sh
# sudhanix-firstlogin-lib.sh — shared logic for first-login bootstrap and
# explicit home-directory migration. Sourced by:
#   * /usr/local/sbin/sudhanix-firstlogin   (XDG autostart, runs as $USER)
#   * /usr/local/sbin/sudhanix-migrate-home (sysadmin tool, runs as root,
#                                            su's to target user)
#
# Idempotent. Fail-soft: every step is wrapped; a failure logs and continues.
# The script never exits non-zero on the user-login path so a buggy bootstrap
# cannot block a graphical session.

# ----- Constants ------------------------------------------------------------

SUDHANIX_VERSION=26
MARKER_REL=".config/sudhanix/v${SUDHANIX_VERSION}-bootstrapped"
QUARANTINE_PREFIX=".config/.pre-sudhanix-${SUDHANIX_VERSION}"
LOG_REL=".cache/sudhanix-firstlogin.log"
NOTES_REL=".sudhanix-migration-NOTES.txt"
SKEL_DIR="/etc/skel"

# Per-app dconf user-db seeds applied on first login. Each file in this
# directory must start with a `# prefix: /net/launchpad/plank/` header line
# naming the dconf prefix; the rest is fed to `dconf load <prefix>`.
#
# Trade-off (loud, on purpose): once we seed user-db, the user "owns" those
# keys forever — future updates to /etc/dconf/db/site.d/* will NOT propagate
# (user-db beats system-db:site in /etc/dconf/profile/user). To re-seed a
# fleet post-rollout, ship a sysadmin reseed tool or bump SUDHANIX_VERSION
# to re-quarantine. The reason we still seed: Plank's first-run auto-detect
# clobbers system-db defaults the moment user-db is empty, and there is no
# upstream knob to disable that behaviour. See cttb-ansible#35.
DCONF_SEED_DIR="/etc/sudhanix/dconf-seeds"

# When SFL_DRY_RUN=1, every step prints what it WOULD do to stdout and
# performs no filesystem mutations. Set by --dry-run on the entry points.
SFL_DRY_RUN="${SFL_DRY_RUN:-0}"

# Stale dotfiles that XFCE 4.18 reads in preference to /etc/xdg defaults,
# plus app autosaves that mask system defaults via the per-user override
# layer (dconf user-db beats system-db:site; xfconf user XML beats /etc/xdg).
# Quarantined — not deleted — so the user can recover anything they care
# about from the quarantine path noted in the migration log.
QUARANTINE_PATHS="
.config/xfce4
.config/lxqt
.config/openbox
.config/plank
.config/dconf
.gtkrc-2.0
.config/gtk-3.0/settings.ini
"

# Items inside the quarantined dirs we want to carry forward (small, safe,
# user-authored). Listed as "<source-rel> <dest-rel>" pairs.
PRESERVE_PAIRS="
.config/gtk-3.0/bookmarks .config/gtk-3.0/bookmarks
"

# Snap → apt profile migrations.  Pipe-delimited 4-tuples:
#   snap_name | snap_subpath_rel | apt_dest_rel | post_copy_fn
# snap_subpath_rel and apt_dest_rel are relative to $HOME.
# post_copy_fn may be empty (no fixup needed).
SNAP_APP_MIGRATIONS="
firefox|snap/firefox/common/.mozilla/firefox|.mozilla/firefox|sfl_post_firefox
"

# ----- Helpers --------------------------------------------------------------

sfl_log() {
    # Append to per-user log; create the cache dir lazily.
    _msg="$1"
    _ts=$(date '+%Y-%m-%d %H:%M:%S')
    if [ "${SFL_DRY_RUN}" = "1" ]; then
        printf '[dry-run] %s\n' "${_msg}"
        return 0
    fi
    mkdir -p "${HOME}/.cache" 2>/dev/null || return 0
    printf '[%s] %s\n' "${_ts}" "${_msg}" >> "${HOME}/${LOG_REL}" 2>/dev/null || true
}

sfl_run() {
    # Wrapper: print intent, then execute (or skip in dry-run mode).
    # Usage: sfl_run "<description>" cmd arg arg...
    _desc="$1"; shift
    if [ "${SFL_DRY_RUN}" = "1" ]; then
        printf '[dry-run] would: %s\n' "${_desc}"
        return 0
    fi
    "$@"
}

sfl_note() {
    # Append a line to the user-visible migration notes file.
    _msg="$1"
    [ "${SFL_DRY_RUN}" = "1" ] && return 0
    printf '%s\n' "${_msg}" >> "${HOME}/${NOTES_REL}" 2>/dev/null || true
}

sfl_already_bootstrapped() {
    [ -f "${HOME}/${MARKER_REL}" ]
}

sfl_init_notes() {
    [ -f "${HOME}/${NOTES_REL}" ] && return 0
    [ "${SFL_DRY_RUN}" = "1" ] && {
        printf '[dry-run] would: write %s\n' "${HOME}/${NOTES_REL}"
        return 0
    }
    cat > "${HOME}/${NOTES_REL}" <<EOF 2>/dev/null || true
Sudhanix ${SUDHANIX_VERSION} home-directory migration notes
=============================================================

This file was created by sudhanix-firstlogin / sudhanix-migrate-home when
your home directory was upgraded from the previous Lubuntu 20.04
desktop layout to the new Sudhanix ${SUDHANIX_VERSION} (XFCE) layout.

Configuration files from the old desktop session were moved aside so the
new system-wide defaults take effect. Your personal data (Documents,
Desktop, Downloads, Pictures, browser bookmarks, Mail, etc.) was NOT
touched.

If something looks wrong or you need to recover a file, look in the
quarantine directory referenced below. To roll back, copy items back to
their original location and log out / log in.

Events:

EOF
}

# ----- Migration steps (each is a no-op when already done) ------------------

sfl_quarantine_stale_configs() {
    _ts=$(date '+%Y%m%d-%H%M%S')
    _dest="${HOME}/${QUARANTINE_PREFIX}.${_ts}"
    _moved_any=0

    for _rel in ${QUARANTINE_PATHS}; do
        _src="${HOME}/${_rel}"
        [ -e "${_src}" ] || [ -L "${_src}" ] || continue

        if [ "${_moved_any}" = "0" ]; then
            if [ "${SFL_DRY_RUN}" = "1" ]; then
                printf '[dry-run] would: mkdir %s\n' "${_dest}"
            else
                mkdir -p "${_dest}" 2>/dev/null || {
                    sfl_log "quarantine: mkdir ${_dest} failed; abort"
                    return 0
                }
                sfl_note ""
                sfl_note "$(date '+%Y-%m-%d %H:%M:%S') — quarantined stale configs"
                sfl_note "  destination: ${_dest}"
            fi
            _moved_any=1
        fi

        # Preserve parent path inside the quarantine so restore is mechanical.
        _parent=$(dirname "${_rel}")

        if [ "${SFL_DRY_RUN}" = "1" ]; then
            _size=$(du -sh "${_src}" 2>/dev/null | awk '{print $1}')
            printf '[dry-run] would: mv %s -> %s/%s  (size %s)\n' \
                "${_src}" "${_dest}" "${_rel}" "${_size:-?}"
            continue
        fi

        mkdir -p "${_dest}/${_parent}" 2>/dev/null || true
        if mv "${_src}" "${_dest}/${_rel}" 2>/dev/null; then
            sfl_log "quarantined: ${_rel} -> ${_dest}/${_rel}"
            sfl_note "    ${_rel}"
        else
            sfl_log "quarantine: mv ${_rel} failed (keeping in place)"
        fi
    done

    if [ "${_moved_any}" = "1" ] && [ "${SFL_DRY_RUN}" != "1" ]; then
        sfl_note "  to restore an item: cp -r '${_dest}/<path>' ~/<path>"
    fi
}

sfl_carry_forward_preserved() {
    # Find the most recent quarantine dir; pull selected items back out.
    # In dry-run mode the quarantine doesn't actually exist yet, so we
    # introspect the live $HOME instead — same items, different parent.
    if [ "${SFL_DRY_RUN}" = "1" ]; then
        _src_root="${HOME}"
    else
        # shellcheck disable=SC2012  # POSIX: ls -t is the simplest way to get newest-first
        _latest=$(ls -1dt "${HOME}/${QUARANTINE_PREFIX}".* 2>/dev/null | head -1)
        [ -n "${_latest}" ] || return 0
        [ -d "${_latest}" ] || return 0
        _src_root="${_latest}"
    fi

    # shellcheck disable=SC2086  # word-splitting on PRESERVE_PAIRS is intentional
    set -- ${PRESERVE_PAIRS}
    while [ "$#" -ge 2 ]; do
        _src_rel="$1"
        _dst_rel="$2"
        shift 2
        _src="${_src_root}/${_src_rel}"
        _dst="${HOME}/${_dst_rel}"

        [ -e "${_src}" ] || continue
        [ "${SFL_DRY_RUN}" != "1" ] && [ -e "${_dst}" ] && continue
        if [ "${SFL_DRY_RUN}" = "1" ]; then
            printf '[dry-run] would: preserve %s across upgrade\n' "${_dst_rel}"
            continue
        fi
        mkdir -p "$(dirname "${_dst}")" 2>/dev/null || true
        if cp -a "${_src}" "${_dst}" 2>/dev/null; then
            sfl_log "preserved: ${_src_rel} -> ${_dst_rel}"
            sfl_note "  preserved across upgrade: ${_dst_rel}"
        else
            sfl_log "preserve: copy ${_src_rel} failed"
        fi
    done
}

sfl_seed_from_skel() {
    # Copy files from /etc/skel into $HOME for any path that does not yet
    # exist in $HOME. Mirrors pam_mkhomedir for fresh users; this path
    # covers users with pre-existing NFS homes (where mkhomedir is a no-op).
    [ -d "${SKEL_DIR}" ] || return 0

    if [ "${SFL_DRY_RUN}" = "1" ]; then
        # Walk the skel tree and report each file that would land in $HOME.
        cd "${SKEL_DIR}" 2>/dev/null || return 0
        find . -mindepth 1 -type f 2>/dev/null | while IFS= read -r _path; do
            _rel=${_path#./}
            _dst="${HOME}/${_rel}"
            if [ ! -e "${_dst}" ]; then
                printf '[dry-run] would: seed %s\n' "${_rel}"
            else
                printf '[dry-run] skip seed (already present): %s\n' "${_rel}"
            fi
        done
        cd "${HOME}" 2>/dev/null || true
        return 0
    fi

    if command -v rsync >/dev/null 2>&1; then
        # --ignore-existing keeps any user-modified file untouched.
        if rsync -a --ignore-existing "${SKEL_DIR}/" "${HOME}/" 2>/dev/null; then
            sfl_log "seeded from ${SKEL_DIR} via rsync (ignore-existing)"
        else
            sfl_log "seed: rsync failed"
        fi
        return 0
    fi

    cd "${SKEL_DIR}" 2>/dev/null || return 0
    find . -mindepth 1 2>/dev/null | while IFS= read -r _path; do
        _rel=${_path#./}
        _dst="${HOME}/${_rel}"
        if [ -d "${SKEL_DIR}/${_rel}" ]; then
            mkdir -p "${_dst}" 2>/dev/null || true
        elif [ ! -e "${_dst}" ]; then
            mkdir -p "$(dirname "${_dst}")" 2>/dev/null || true
            cp -a "${SKEL_DIR}/${_rel}" "${_dst}" 2>/dev/null \
                && sfl_log "seeded: ${_rel}"
        fi
    done
    cd "${HOME}" 2>/dev/null || true
}

sfl_seed_user_dconf() {
    # Pre-populate the user's dconf user-db with canonical site defaults for
    # apps that auto-detect/clobber on a fresh user-db (Plank in particular).
    # Runs after sfl_seed_from_skel so .dockitem files are in place, and
    # before xfce4-session forks Plank.
    [ -d "${DCONF_SEED_DIR}" ] || return 0

    if ! command -v dconf >/dev/null 2>&1; then
        sfl_log "dconf seed: dconf binary missing, skip"
        return 0
    fi

    # dconf write needs a session bus. Xsession.d/40x11-common_xsessionrc
    # exports DBUS_SESSION_BUS_ADDRESS before this script runs. If absent,
    # fall back to a wrapper bus so the user-db still gets seeded.
    _wrap=""
    if [ -z "${DBUS_SESSION_BUS_ADDRESS:-}" ]; then
        if command -v dbus-run-session >/dev/null 2>&1; then
            _wrap="dbus-run-session --"
            sfl_log "dconf seed: DBUS_SESSION_BUS_ADDRESS unset, using dbus-run-session"
        else
            sfl_log "dconf seed: no session bus and dbus-run-session missing, skip"
            return 0
        fi
    fi

    _seeded_any=0
    for _seed in "${DCONF_SEED_DIR}"/*.txt; do
        [ -f "${_seed}" ] || continue

        _prefix=$(awk '/^[[:space:]]*#[[:space:]]*prefix:/ { sub(/^[[:space:]]*#[[:space:]]*prefix:[[:space:]]*/,""); print; exit }' "${_seed}")
        if [ -z "${_prefix}" ]; then
            sfl_log "dconf seed: ${_seed} has no '# prefix:' header, skip"
            continue
        fi

        _name=$(basename "${_seed}" .txt)

        if [ "${SFL_DRY_RUN}" = "1" ]; then
            printf '[dry-run] would: dconf load %s < %s\n' "${_prefix}" "${_seed}"
            continue
        fi

        # Strip the `# prefix:` directive line; dconf-load tolerates other
        # comments but the directive is ours, not its.
        if grep -v '^[[:space:]]*#[[:space:]]*prefix:' "${_seed}" | ${_wrap} dconf load "${_prefix}" 2>>"${HOME}/${LOG_REL}"; then
            sfl_log "dconf seed: ${_name} -> ${_prefix}"
            sfl_note "  seeded user-db dconf: ${_name} (${_prefix})"
            _seeded_any=1
        else
            sfl_log "dconf seed: ${_name} -> ${_prefix} FAILED"
        fi
    done

    if [ "${_seeded_any}" = "1" ]; then
        sfl_note "    you can rearrange these defaults; your changes will persist."
    fi
}

sfl_set_xfce_session_pref() {
    _dmrc="${HOME}/.dmrc"
    if [ "${SFL_DRY_RUN}" = "1" ]; then
        printf '[dry-run] would: write %s with Session=xfce\n' "${_dmrc}"
        return 0
    fi
    cat > "${_dmrc}" <<'EOF' 2>/dev/null || return 0
[Desktop]
Session=xfce
EOF
    chmod 0644 "${_dmrc}" 2>/dev/null || true
    sfl_log "wrote ~/.dmrc (Session=xfce)"
}

# Seed ~/.config/xfce4/helpers.rc with campus defaults so exo-helper-1
# (Thunar "Open in Terminal", xfce4-panel "Open URL", vajra Quick Links,
# anything that exo-open's) has a registered handler from the first
# session. Without this the user sees "Failed to execute default Web
# Browser" / "no terminal emulator configured" dialogs until they wander
# into Settings → Preferred Applications.
#
# Welcome customizer's apply_settings() rewrites the same file with the
# user's choices — this seed is the safety net for the time between
# first login and the first Apply click.
sfl_set_default_helpers() {
    _rc="${HOME}/.config/xfce4/helpers.rc"
    if [ "${SFL_DRY_RUN}" = "1" ]; then
        printf '[dry-run] would: seed %s with TerminalEmulator + WebBrowser\n' "${_rc}"
        return 0
    fi
    mkdir -p "${HOME}/.config/xfce4" 2>/dev/null || return 0
    # Don't clobber a pre-existing helpers.rc (a returning user may have
    # set preferences via the GUI). Only write when absent.
    [ -e "${_rc}" ] && { sfl_log "helpers.rc already exists; leaving as-is"; return 0; }
    cat > "${_rc}" <<'EOF' 2>/dev/null || return 0
TerminalEmulator=xfce4-terminal
WebBrowser=firefox
EOF
    chmod 0644 "${_rc}" 2>/dev/null || true
    sfl_log "wrote ~/.config/xfce4/helpers.rc (TerminalEmulator + WebBrowser defaults)"
}

sfl_write_marker() {
    if [ "${SFL_DRY_RUN}" = "1" ]; then
        printf '[dry-run] would: write marker %s\n' "${HOME}/${MARKER_REL}"
        return 0
    fi
    mkdir -p "${HOME}/.config/sudhanix" 2>/dev/null || return 0
    {
        printf 'version=%s\n' "${SUDHANIX_VERSION}"
        printf 'timestamp=%s\n' "$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
        printf 'hostname=%s\n' "$(hostname 2>/dev/null || echo unknown)"
    } > "${HOME}/${MARKER_REL}" 2>/dev/null || true
    sfl_log "marker written: ${MARKER_REL}"
}

# ----- Snap → apt profile migration ----------------------------------------

sfl_post_firefox() {
    _dst="$1"
    _ini="${_dst}/profiles.ini"
    [ -f "${_ini}" ] || return 0

    # Strip the absolute snap prefix, leaving just the profile dir name.
    sed -i \
        "s|^Path=${HOME}/snap/firefox/common/.mozilla/firefox/||" \
        "${_ini}" 2>/dev/null || true

    # For any Path line now relative (no leading /), ensure IsRelative=1.
    sed -i \
        '/^Path=[^/]/{ n; s/^IsRelative=0/IsRelative=1/; }' \
        "${_ini}" 2>/dev/null || true

    sfl_log "firefox: profiles.ini rewritten (snap abs paths -> relative)"
}

sfl_migrate_snap_apps() {
    printf '%s\n' "${SNAP_APP_MIGRATIONS}" | while IFS='|' read -r _name _snap_sub _apt_dest _post_fn; do
        # Skip blank lines (the leading/trailing newlines in the heredoc).
        [ -n "${_name}" ] || continue

        _snap_src="${HOME}/${_snap_sub}"
        _apt_dst="${HOME}/${_apt_dest}"

        if [ ! -d "${_snap_src}" ]; then
            sfl_log "${_name}: no snap profile at ${_snap_sub}, skip"
            continue
        fi

        if [ -e "${_apt_dst}" ]; then
            sfl_log "${_name}: apt path exists (${_apt_dest}), skip (idempotent)"
            continue
        fi

        if [ "${SFL_DRY_RUN}" = "1" ]; then
            printf '[dry-run] would: cp -a %s %s\n' "${_snap_src}" "${_apt_dst}"
            continue
        fi

        mkdir -p "$(dirname "${_apt_dst}")" 2>/dev/null || continue
        if cp -a "${_snap_src}" "${_apt_dst}" 2>/dev/null; then
            sfl_log "${_name}: migrated snap profile -> ${_apt_dst}"
            sfl_note "  ${_name}: snap profile copied to ~/${_apt_dest}"
            if [ -n "${_post_fn}" ] && command -v "${_post_fn}" >/dev/null 2>&1; then
                "${_post_fn}" "${_apt_dst}"
            fi
        else
            sfl_log "${_name}: cp failed; snap profile intact at ${_snap_sub}"
        fi
    done
}

# ----- Top-level orchestrator ----------------------------------------------

# gh-36: the Super_L → app-menu binding was corrected in the role's
# /etc/xdg xfce4-keyboard-shortcuts.xml template (gh-61/gh-63: whiskermenu,
# which self-toggles on a second press). But xfconfd reads the per-user
# cache at ~/.config/xfce4/xfconf/.../xfce4-keyboard-shortcuts.xml first,
# and an already-bootstrapped user's stale cache still points Super_L at
# the old sudhanix-toggle-appmenu wrapper — so the corrected system
# default never wins. Removing the per-user cache once lets xfconfd
# re-seed from the (fixed) /etc/xdg template at the next panel start.
# Self-sentineled so it fires exactly once per user, INCLUDING users
# already past the firstlogin marker gate.
sfl_reseed_keyboard_shortcuts() {
    _sentinel="${HOME}/.config/sudhanix/kb-shortcuts-gh36-reseeded"
    [ -f "${_sentinel}" ] && return 0
    _kb="${HOME}/.config/xfce4/xfconf/xfce-perchannel-xml/xfce4-keyboard-shortcuts.xml"
    if [ "${SFL_DRY_RUN}" = "1" ]; then
        printf '[dry-run] would: rm %s ; mark %s\n' "${_kb}" "${_sentinel}"
        return 0
    fi
    mkdir -p "${HOME}/.config/sudhanix" 2>/dev/null || return 0
    if [ -f "${_kb}" ]; then
        rm -f "${_kb}" 2>/dev/null \
            && sfl_log "gh-36: removed stale per-user xfce4-keyboard-shortcuts.xml (reseed from /etc/xdg)"
        # Nudge xfconfd/panel to re-read if a live session is present;
        # fail-soft when there is no DISPLAY (TTY/ssh bootstrap).
        if [ -n "${DISPLAY}" ] && command -v xfce4-panel >/dev/null 2>&1; then
            xfce4-panel --restart >/dev/null 2>&1 || true
        fi
    else
        sfl_log "gh-36: no per-user kb-shortcuts cache; system /etc/xdg default already authoritative"
    fi
    : > "${_sentinel}" 2>/dev/null || true
}

sfl_run_bootstrap() {
    # Sanity: $HOME must be set and exist. In dry-run we don't need write
    # access (we make no changes); in real-run we do.
    [ -n "${HOME}" ] || return 0
    [ -d "${HOME}" ] || return 0
    if [ "${SFL_DRY_RUN}" != "1" ]; then
        [ -w "${HOME}" ] || return 0
    fi

    # gh-36 corrective reseed runs for EVERY user exactly once, before the
    # firstlogin marker gate — already-bootstrapped users need it too.
    sfl_reseed_keyboard_shortcuts

    if sfl_already_bootstrapped; then
        if [ "${SFL_DRY_RUN}" = "1" ]; then
            printf '[dry-run] %s already bootstrapped (marker %s present); no-op\n' \
                "${HOME}" "${MARKER_REL}"
        else
            sfl_log "already bootstrapped (marker present); exit 0"
        fi
        return 0
    fi

    if [ "${SFL_DRY_RUN}" = "1" ]; then
        printf '\n=== sudhanix-firstlogin dry-run for %s ===\n' "${HOME}"
    else
        sfl_log "begin bootstrap (sudhanix v${SUDHANIX_VERSION})"
    fi

    sfl_init_notes
    sfl_quarantine_stale_configs
    sfl_carry_forward_preserved
    sfl_migrate_snap_apps
    sfl_seed_from_skel
    sfl_seed_user_dconf
    sfl_set_xfce_session_pref
    sfl_set_default_helpers
    sfl_write_marker

    [ "${SFL_DRY_RUN}" != "1" ] && sfl_log "end bootstrap"
}
