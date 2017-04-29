# OVERVIEW

Sets up the necessary stuff to accept logs from other sources and store
them/rotate them as needed (initial implementation done with rsyslog).

Logs should be stored on a separate data partition, right now a zfs dataset
mounted at /logs.

The tasks/main.yml assumes that the directory /logs/ exists, and
is writable by the 'syslog' user. Current set up to satisfy this
requirement: the syslog user is in the 'adm' group, and /logs/ is:
owner root, group adm, mode rwxrwxr-x.
