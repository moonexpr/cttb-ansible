To: Frank, Jerry
Subject: The sysadmin toolkit is live, and it is going to change how you work

Frank, Jerry,

Thank you both for carrying the day-to-day of the CTTB network as long as you have. Much of what each of us knows about these boxes has lived in one head at a time, and I could not be more glad to change that today. The sysadmin toolkit we had been building is now committed to the `cttb-ansible` repo, tagged as its first release, and it is built for both of you to pick up and run.

Here is what I am excited for you to feel: the work you have been doing by hand now has a helper standing right next to it. There are skills for the things that come up most, I.e., querying and editing LDAP, authoring and styling wiki pages, shelling into any host or container, running ansible-vault without a password prompt, registering a device out of the block13 quarantine pool, and building and publishing the vajra package to `apt.cttb`. Underneath the skills sit the Python and shell tools they wrap. None of them hold a secret. Each one reads your credentials from the macOS Keychain, or from a local `.env` file on Linux, so nothing sensitive ever touches the repo. The tasks that used to eat an afternoon are about to take minutes.

Getting started takes three steps. Clone `moonexpr/cttb-ansible` and open it in Claude Code. Copy `.claude/.env.example` to `.claude/.env` and fill in your own credentials, or store them in the Keychain, which is the cleaner path on a Mac. Then read `CLAUDE.md` at the repo root. That file is self-contained. The skill catalog, the tooling reference, and the operating conventions all live there, so you will not need anything from my personal setup to make it work on your machine.

The release notes walk through the same ground with a bit more detail: https://github.com/moonexpr/cttb-ansible/releases/tag/sysadmin-toolkit-v1.0

Try it against something low-stakes first, a wiki page read or an LDAP lookup, and watch how fast it moves. Then tell me where it feels rough, because the tooling gets sharper the more two more sets of hands run it, and yours are the two I most want on it.

Warm regards,
John Ott Chandara
