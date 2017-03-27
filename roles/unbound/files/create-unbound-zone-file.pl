#!/usr/bin/env perl

# Purpose:
#     To create the content to resolve the switch names to IP addresses,
#     and vice versa in the unbound config file zone-cttb.
# Usage:
#     cat switch-ips.txt | ./create-unbound-zone-file.pl | sort -V > unbound-switch-info.txt
#     Then read in the file "unbound-switch-info.txt" into the "zone-cttb" file.
# Rui Liu, CTTB, 2017-03-26.

while ($line=<>) {
    if ($line =~ /^(10.11.12.\d+|^172.\d+.\d+.\d+)\s+(sw-\S+)\s+(.*)$/) {
        $ip = $1;
        $sysname = $2;
        $line1 = 'local-data: "' . $sysname . '.cttb. IN A ' . $ip . '"';
        $line2 = 'local-data-ptr: "' . $ip . ' ' . $sysname . '.cttb."';
        print $line1, "\n";
        print $line2, "\n";
        # If the ip is 172.30.7.*, add another 2 lines, replacing .7 with .20.
        if ($ip =~ /172\.30\.7\./) {
            $line3 = $line1;
            $line3 =~ s/172\.30\.7\./172.30.20./;
            $line4 = $line2;
            $line4 =~ s/172\.30\.7\./172.30.20./;
            print $line3, "\n";
            print $line4, "\n";
        }
    }
}
