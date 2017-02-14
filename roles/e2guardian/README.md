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
By default the _naughtyuness_ level is set to 50 (small children) and you
should really tune it for best results.

## Assing uses to groups
Groups are matched by ip in _lists/authplugins/ipgroups_.

All groups share common banned and whitelists in _lists/_ and then override/add
their own using _lists/fX_.

All definitions are done through the host variable filtering_groups, with
defaults in the role for the F1 default group E2G ships with.

## Overrides
Not everythins needs to be overridden so for many settings config files point
straight to the base file.

Where overrides are needed the directive will point to the _lists/fX_ dir which
will include the base file plus specifying the overrides

To allow for lists reuse and minimizing config changes we use a _cttb_ directory
that contains various overrides that can be shared across groups, for example
dvgs and dvbs can share an _igdvs_ list.
