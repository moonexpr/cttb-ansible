#!/bin/sh
# Remove stale Chrome singleton locks left by NFS home directories.
# Chrome locks the profile with a symlink pointing to hostname-pid.
# If that host isn't this machine, the lock is stale.
CHROME_DIR="$HOME/.config/google-chrome"
LOCK="$CHROME_DIR/SingletonLock"
if [ -L "$LOCK" ]; then
    TARGET=$(readlink "$LOCK")
    LOCK_HOST=$(echo "$TARGET" | sed 's/-[0-9]*$//')
    if [ "$LOCK_HOST" != "$(hostname)" ]; then
        rm -f "$LOCK" "$CHROME_DIR/SingletonSocket" "$CHROME_DIR/SingletonCookie"
    fi
fi
