- get ulogd logs rotate by logrotate
- Possibly even if connections are rejected, already established connection may
  still continue. In theory conntrack can be usef like this to kill the
  connection: #$CONNT -D -s $IP. However that needs an ip and some of the rules
  with ipsets are ranges that won't work with conntrack. I could do a conntrack
  --flush, but that will kill connections for everybody. In practice this may not
  be a problem as we're trying to prevent internet browsing and visiting a new
  page would b a new connection.
