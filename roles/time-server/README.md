# Overview
By default this role installs the ntp server daemon and uses the upstreams
servers defined in the defaults value which has the local lan ntp server
(ntp.cttb) and ntp.ubuntu.com as fallback. Override as needed in the host or
group variable files. The override is obviously necessary on the server
instance.

# DHCP problems
Note that if the server has dhcp enabled this will fetch ntp info from the dhcp reponse and override settings in ntp.conf. this means that all your servers will be superside by the local one, except that if this is the local one you get a loop and nothing works.

***MANUAL CHANGE***
for now edit /etc/dhcp/dhclient.conf and remove the ntp-servers option
