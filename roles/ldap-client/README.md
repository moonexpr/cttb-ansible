# OVERVIEW
This role contains code to setup an ldap client

# REQUIRED
Host that need ldap installed MUST be added to the correct group in
ansible/hosts.
At a minimum a host needs to be added to the "other-ldap-clients" so that its
ldap_groups can be defined accordingly

# VARIABLES
for things to work you need to setup a bunch of variables.  
Default are in place, but override as needed.
