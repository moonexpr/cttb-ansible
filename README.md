# Overview
Information about our structure for ansible. Inspired by:
- https://github.com/enginyoyen/ansible-best-practises
- http://docs.ansible.com/ansible/playbooks_best_practices.html

Running playbooks or other ansible operations should be carried out with the
respective scripts in utils/. Do not run this scripts from another path or
directly call ansible or ansible-playbook.

*ALWAYS RUN THE SCRIPTS FROM THE ROOT OF THE REPOSITORY* using a relative path
such as _utils/pb_.

# Migrations
If you are migrating a machine to use a new role/setup and need to do some
cleanup use the playbook to do the job. For example when migrating
unbound servers to the new unbound role I wanted to use
/etc/unbound/blocked-sites as a directory but I used to use a file with that
name as a blacklist. As a result I had to rm that file before the new role
succeeded. A task like this should be contained in a special playbook that
installs the new role.

# Git
- Ignore the log/ directory and the tmp/ dir that should be setup in the ansible directory

# Config
- The config file resides in the samedir as this stuff
- it uses a bunch of $ANSIBLE_VARIABLES to set things such as host file and roles dir

# Playbooks
- all playbooks are stored in plays/
- Q: what do I do with individual hosts such as the jumpbox or the nfs server?
  should they get their own playbook? or should I just have a python script
  that deals with them? but then where do I draw the line? If I have things
  specific to only one host try to use variables instead
- T: no need for playbooks, just use roles (see below)

# Roles
- Initially I used the convention of external/ for roles downloaded by galaxy
  and internal/ for our own stuff but prefixes are just a better way to go
  since we may have say a nfs role that extends a galaxy role.
- Use a common cttb. prefix for all our roles
- Any role without a cttb. prefix is coming from galaxy/other source (look for
  a readme inside then)
- You may have a question if something should go into a role or not. As a rule
  of thumb, it code is not shared/reused put it into a play
- T: what if I only used roles, so there's shared reused roles, but also have
  roles that are specific to one host or group. Maybe can have roles such as
  cttb.hosts.hostname to differentiate and the inventory may or may not include
  that so I just run whatever roles are there

# Assets
- large files such as .deb or .tar.gz are stored on the webserver and fetched with a uri_get
- they are not versioned as it's not great to store them in git
- this directory should be backed up as part of the web server backup

# Misc
I really like what they've done at debops.org, but it seems too complex and too
much of a commitment for us atm so I'm sticking with our own stuff + homegrown
