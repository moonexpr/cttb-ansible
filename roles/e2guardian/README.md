# Overview
This role configures E2Guardian.

At a very minimum you *must set filter\_ip* or E2G will only listen on
localhost by default.

By default variables are optimized for a largish site. If you need it for
smaller installations a bunch of tunings harcoded in the config may need to be
looked at.

E2Guardian main config files holds some common directive but then real filtering
is done with per group config _e2guardianfX.conf_ where X is the group number.

# Filtering configuration
Everything is controlled in two places:
- the filtering_groups variable, defined in the host vars for the gateway
- the _overrides_ directory under files, used to ban or whitelist phrases,
  sites, etc. This directory contains directories named after the group name
  defined in filtering_groups. Names must match for overrides to be loaded

Please note that by default the _naughtyuness_ level is set to 50 (small
children) and you should really tune it for best results.

## Assing users to groups
Groups are matched by ip in _lists/authplugins/ipgroups_. This is generated
from filtering_groups based on the ips field. The field can be any of the
following:
- a straight ip, 192.168.0.1
- a subnet with netmask, 192.168.1.0/255.255.255.0
- a range, 192.168.1.0-192.168.1.255

Add as many combinations as you'd like, one per line, and they will all be
assigned to the group they belong to.

All groups share common banned and whitelists in _lists/_ and then override/add
their own using _fX lists_.

All definitions are done through the host variable filtering_groups, with
defaults in the role for the F1 default group E2G ships with.
