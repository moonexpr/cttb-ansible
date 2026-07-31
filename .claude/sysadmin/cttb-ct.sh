#!/bin/sh
# Compatibility forwarder. The sysadmin toolkit moved to utils/ so it is usable
# without reference to Claude; canonical path is utils/cttb-ct.sh.
exec "$(dirname "$0")/../../utils/cttb-ct.sh" "$@"
