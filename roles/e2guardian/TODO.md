# TODO
- see if I can automate picking the ip for the filtering_ip , maybe lookup
  "lan" interface from the  server_interfaces variable, but not sure how
  portable that is
- add some field to automatically add stuff to overrides
- if I remove a filter list or something, it does not get remove from the
  actual server, which may generate confusion if I go and look. figure
  something out
- figure out a better way to handle group inheritance at
  variable definition level. For example with adult and
  adult_no_bypass, the latter should only have one field
  defined and inherit the rest, but atm I have to repeat
  the entire data structure.
