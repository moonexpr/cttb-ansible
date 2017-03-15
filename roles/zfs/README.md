# Overview
The role stuff is pretty bad. There's no module for it, and doing it with
commands is just no idempotent and breaks a lot of stuff. It's good for initial
setup on a fresh box, but any attempt to re-run will lead to potential data
loss and for sure errors in the play

It's just faster to set up a new box consistently from a variable definition,
that's its main use right now.
