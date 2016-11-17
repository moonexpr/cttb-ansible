# Overview
This role installs and configure asterix, setup our phones tftp (not dnsmasq is
still the tftp server and needs to be configured to point ips in the .6 range
to asterix for config).

# TODO
This first version of the role is simply a way to copy all the files in the
right place so I don't forget things or take forever, but it's not a clear
role. Down the line, when we have a CMDB, this shuold be rewritten to generate
most of the configs.

# Packages
Install the relevant debs, see tasks/main.yml

# External Files
While some files are provided as part of the role, Asterix still depends on a
remote repository on the overseer to fetch larger artefacts not stored in
git/here.

# Configuration files
All asterix configuration files

## Sip

## Extensions

## Voicemail
Once put in place we can not override it again because users may have changed
their pwd.
If a user uses their phone to change the pin ansible wouldn't know.  Eventually we
should use "externpass" to update the CMDB from which the config file should be
regenerated, but for now we don't and just sync the voicemail file routinely.

### Voicemail passwords
There doesn't seem to be a way to encrypt these in any way.
## Custom bits
There are a number of custom pieces in the configs that cannot be generated or
managed by ansible at runtime and needs to come from a static bit we edit

### IGDVS PA System

# Google voice

# Sounds
/var/lib/asterisk/sounds/custom/

# TFTP
/var/lib/tftpboot/
make sure all files are readable by tftp
BUG: right now all files must be world readable which sucks since they contain
passwords. I need to figure out why tftp can't otherwise read them.
