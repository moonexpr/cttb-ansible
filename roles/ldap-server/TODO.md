# TODO

## Edit /etc/ldapscripts/ldapscripts.conf so that:
- SERVER="ldap://ldap-srv.cttb"
- SUFFIX="dc=cttb" # Global suffix
- BINDDN="cn=admin,dc=cttb"
- LDAPBINOPTS="-ZZ"

## Change the mode of /etc/ldapscripts/ldapscripts.password to 600.

## Add the password into /etc/ldapscripts/ldapscripts.password.
- Within vi, do ":set binary", ":set noeol", then add the password,
  otherwise the newline at the eol will cause an "invalid credential" error.
