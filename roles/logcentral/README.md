# OVERVIEW

Sets up the necessary stuff to accept logs from other sources and store
them/rotate them as needed (initial implementation done with rsyslog).

Logs should be stored on a separate data partition, right now a zfs dataset
mounted at /logs.
