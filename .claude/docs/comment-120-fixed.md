Fixed on `main` (`85b1fc42`), together with a second defect the fix exposed.

`hosts:` is now `all` with the stage-2 header convention, so `-l` scopes the run. Beyond the pinning, the play also lacked `become: true` — which had gone unnoticed because every file the `common` role manages already existed and matched, making `copy` a no-op that needs no privileges. The first genuinely new file it tried to write failed with `Destination /etc/systemd/network not writable`. Both are in the same commit.

Verified by the thing that needed it: `utils/pb base -l cttb_hosts --tags wake_on_lan` now applies the #118 wake-on-LAN arming across the reachable fleet, which was impossible through a play before.

Worth noting the pinned name `drbu-cs-lab-pc1` does not exist in `inventory/sudhanix26_hosts.ini` at all, so this play matched nothing against the default inventory — it cannot have run successfully in its pinned form for some time.
