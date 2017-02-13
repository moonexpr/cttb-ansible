# Overview This role sets up a firewall using firehol

*PLEASE NOTE*: at this time the role is hardcoded for the gateway as no other
box runs a firewall atm. This may change in the future

Also to avoid possible problems we don't automatically apply the changes. After
deploying new firehol configs etc log onto the box and use firehol try to apply
the changes.

# Time based internet This role supports time based internet limits by
blacklisting ips that need to be limited by default and whitelisting their
access only during the designated times. Implementation is in
tasks/timelimits.yml and the configuration is handled through the
timed_internet variable. Hours of the day are in 24hrs format. Please see more
information below in the Time format section to get a sense of how to use the
day and hour fields.

A script called by cron adds and removes ips from a blacklist as needed. Script
is populated by ansible based on variable definition (see below).

Entire ranges such as dvbs or dvgs use their own ipsets and are controlled by
cron at range level without the need for variable definition or scripts.

The variable is defined as such:

timed_internet:
  - label: group name
    type: ip|net # if ip, expect to add individual ips, if net adds networks (/24, etc), which is faster to search through for the kernel. This is useful when blocking groups like dvbs
    ips:
      - ip1
      - ip2
    periods:
      - days: "mon,wed" # supports same syntax as crontab, with ranges etc
        on_at: 7 # again hrs in 24hrs format, that's 7am
        off_at: 12
      - days: sun
        on_at: 10
        off_at: 20
  - label: else
    type: net
    ips:
      - ip3/24
      - ip4/32
    periods:
      - days: fri
        on_at: 7
        off_at: 12
      - days: sun
        on_at: 10
        off_at: 20

## Time format
The day and time field are user to build crontabs to add and remove ips from
the blacklist. As such they respect the crontab format as explained in the man
page. This is the relevant snippet:

Ranges of numbers are allowed. Ranges are two numbers separated with a hyphen.
The specified range is inclusive. For example, 8-11 for an "hours" entry
specifies execution at hours 8, 9, 10 and 11.

Lists are allowed. A list is a set of numbers (or ranges) separated by commas.
Examples: "1,2,5,9", "0-4,8-12".

Step values can be used in conjunction with ranges. Following a range with
"<number>" specifies skips of the number's value through the range. For
example, "0-23/2" can be used in the hours field to specify command execution
every other hour (the alternative in the V7 standard is
"0,2,4,6,8,10,12,14,16,18,20,22"). Steps are also permitted after an asterisk,
so if you want to say "every two hours", just use "\*/2".

Names can also be used for the "month" and "day of week" fields. Use the first
three letters of the particular day or month (case doesn't matter). Ranges or
lists of names are not allowed.

## Important limitations and gotchas
Because of the way time limits are implemented (cron based) there is a possible
race condition that could lead to internet being blocked during an open window
(for example is the box gets rebooted during an open window) or internet
remaining available after the window (if the box is down when cron is supposed
to run to reinstate the block)
