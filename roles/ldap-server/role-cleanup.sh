#!/bin/bash

# Script to clean up effects of previous ansible tasks to install an LDAP
# server.

rm -rf /etc/ssl/cttb*.info
rm -rf /etc/ssl/private/ldap-srv*.pem

rm -rf /etc/{ldap,ssl}/{.required-tls,.loaded-init-content,.loaded-certs}

rm -rf /etc/{ldap,ssl}/ldifs/

apt purge -y slapd ldap-utils gnutls-bin ssl-cert
