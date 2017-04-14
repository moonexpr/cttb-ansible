# OVERVIEW

This module configures unbound. There are variables to set things up so that it
works both for the igdvs and for adults.

We use unbound as an internal both recursive and auth nameserver for the .cttb
zone. Unbound is technically not an auth ns so it has some limitation, chiefly
no CNAMEs. As such all records are As.

# Make changes to the CTTB Zone
Edit the group_vars/unbound file and your name and ip there and the role will
take care of generating the A and PTR records.

# AD-HOC STUFF
JGS has a stats process on a specific computer that requires the unbound log
file to process. Right now a ssh keys is installed on all unbound servers to
scp the file over to that stats machine. This is done with a cronjob in the
administrator's crontab running at a few mins past midnight (compressing and
rotating the logs takes less than a minute right now; this may fail if the log
grows and takes longer).
