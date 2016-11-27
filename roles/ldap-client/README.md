# IMPORTANT
SSL steps still need to be done manually:

Copy the server certificate for server verification[edit]
sudo scp -p administrator@ldap-srv.cttb:/etc/ldap/cttb-cacert.pem /etc/ldap/

# OVERVIEW
This role contains code to setup an ldap client

# VARIABLES
for things to work you need to setup a bunch of variables. Default are in
place, but override as needed
