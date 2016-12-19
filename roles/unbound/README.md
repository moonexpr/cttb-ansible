# OVERVIEW

This module configures unbound. There are variables to set things up so that it
works both for the igdvs and for adults.

# AD-HOC STUFF
JGS has a stats process on a specific computer that requires the unbound log
file to process. Right now a ssh keys is installed on all unbound servers to
scp the file over to that stats machine. This is done with a cronjob in the
administrator's crontab running at a few mins past midnight (compressing and
rotating the logs takes less than a minute right now; this may fail if the log
grows and takes longer).
