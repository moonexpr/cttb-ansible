# OVERVIEW
Basic setup for server machines including more static configs to ensure no
mishups if we mess up somewhere else (for example dns settings)

In network interfaces we set up special networking for things like servers that
require interfaces with special names, bridging and/or bonding.

# NET INTERFACES
The server role has a taskset to deal with network interfaces in case it
was needed to name them or do something with them other than default (ie a
firewall or host with multiple interfaces).

See source for more info.

# DHCLIENT
if you are setting up a gateway you probably don't want dhcp internal interface
to mess with your routes. If you still use dhcp, which you probably shouldn't,
then you can set /etc/dhcp/dhclient.conf to not set the routes by removing
"routes" from the parameters it requests as such:

request subnet-mask, broadcast-address, time-offset, routers, <--- REMOVE
        domain-name, domain-name-servers, domain-search, host-name,
        dhcp6.name-servers, dhcp6.domain-search, dhcp6.fqdn, dhcp6.sntp-servers,
        netbios-name-servers, netbios-scope, interface-mtu,
        rfc3442-classless-static-routes, ntp-servers;

# Bonding
In the case of Bonding order matters so in the host's variable file the bond interface should be the last one to be declared.
