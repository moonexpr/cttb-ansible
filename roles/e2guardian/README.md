# Overview
This role configures E2Guardian.

At a very minimum you *must set filter\_ip* or E2G will only listen on
localhost by default.

By default variables are optimized for a largish site. If you need it for
smaller installations a bunch of tunings harcoded in the config may need to be
looked at.

E2Guardian main config files holds some common directive but then real filtering
is done with per group config _e2guardianfX.conf_ where X is the group number.

# Configuration variables
Below you will see references to _variables_. These should all be in the
hosts_var for the host you're installing, but there are also some sane defaults
in _defaults/main.yml_. For example the global lists are almost never
overridden and so often the variable only exists in the default file.

# Filtering configuration
Everything is controlled in 3 places:
- the filtering_groups variable, defined in the host vars for the gateway
- the _overrides_ directory under files, used to ban or whitelist phrases,
  sites, etc. This directory contains directories named after the group name
  defined in filtering_groups. Names must match for overrides to be loaded
- the global cttb lists in _cttb-lists_ with banned sites, exceptions etc that
  all groups include

This helps a great deal to avoid duplication or missing stuff out, ie blocking
something in a group but forgetting to block it into another or the same for
whitelisting.

## Adding lists
To add either an override list or a global list you need to do two things:
- explicitly declare the list to be added in the variable, either
  filtering_groups in the override section or cttb_global_lists
- add the file under the corresponding override directory or cttb-lists directory
- if the list was previously in the default_lists, ie lists that are not
  overridden, it needs to be removed from there or otherwise it will containue
  to be ignored.

## Global lists
All the filtering groups share some cttb wide lists. If a new bad site appears
that makes sense to be banned for everybody, it should end up in these lists
and not in specific group lists. Likewise if an obviously good site gets
banned, it makes sense to share the whitelisting with everybody.

### Specific consideration for kids
If you want to whitelist a site for a kid, it makes sense to put it in CTTB
list since if it's ok for a kid it's ok for everybody else who may need that
later (a teacher maybe).

On the other hand exception should be treated carefully as something that may
be ok to be accessed by an adult should not necessarily be seen by a kid. So
when for example you whitelist something for adults ask yourself, should a kid
or a "restricted" group see this? if yes put it in CTTB list, if not, put it in
the specific group.

## Removing lists
Please note that as of this time removing a list from the above two places will
not result in the removal of such list from the server itself. This could lead
to some confusion if someone was to ssh into the server looking to debug a
problem and not look at the defined lists. That said configs are correctly
regenerated to not look at the removed list anymore so the behavior is correct,
it's just the file is left behind.

It's on the TODO.md to do something about this.

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

*PLEASE NOTE: by default unmatched clients will be assigned to filtering group
1.*

In our case adult is the default group for any ip filtered so group order and
id in the configuration variable is very important.

# Banned and unfiltered groups
Ips that should be banned from the internet or completely bypass the content
filter are handled at firewall level as this is much faster than getting them
through E2Guardian. Please see the Firehol role for that.
