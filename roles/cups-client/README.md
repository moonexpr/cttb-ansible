# OVERVIEW

By default this role setup the computer to use a remote print server and will
expect cups_srv to be set. If you want to use a local cups, ie install cupsd,
use the cups-server role.

If you set cups_default_queue this will set the default printer.

*IMPORTANT*
the client pkg conflicts with the server one and will remove server packages.
This is because a cups server should not ever be a desktop needing to print to
something else
