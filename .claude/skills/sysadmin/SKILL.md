---
name: sysadmin
user-invocable: true
argument-hint: "[the sysadmin request]"
description: >
  Project-scoped router for CTTB sysadmin work. Classifies an open-ended ops
  request to exactly one narrower unit skill (`/ldap`, `/wiki-author`,
  `/cttb-host`, `/cttb-vault`, `/github-issues`) and hands off. Triggers on
  `/sysadmin <request>` and on ambiguous ops phrasings ("add a user to a
  group", "what's the IP of wiki-2404", "shell into the LDAP container",
  "file a bug for this"). Routes only — never duplicates the units' content.
---

## Routing table

| Intent | Unit skill |
|--------|-----------|
| Look up / mutate LDAP users, groups, posixGroup, passwords | `/ldap` |
| Draft, edit, upload, style, or delete a `wiki.cttb` page; sitenotice; system messages; Lockdown pages | `/wiki-author` |
| Shell into / run a command on a CTTB host or container | `/cttb-host` |
| Edit / view / encrypt / decrypt / rekey an Ansible vault file | `/cttb-vault` |
| File an actionable defect / task / missing feature on GitHub | `/github-issues` |

If the request bundles several domains, split it and route each piece independently.

## Disambiguation discipline

The router is **generic** and must not bias toward any unit — `/wiki-author` least of all — on a single-keyword match. A wrong early commit costs a full wasted investigation in the wrong domain.

- **Don't route on one word.** "Group", "page", "down", "access", "walled garden" each have senses in more than one unit. Match on the whole request — object, verb, and what a fix would touch.
- **Shared-sense jargon is infra-first.** A place / building / host name + a connectivity-or-state verb ("walled garden", "can't reach", "no internet", "down", "isolated", "captive") is a **network/DNS/host** problem → `/cttb-host` (then DNS/dnsmasq/unbound), **not** `/wiki-author`. (2026-05-19: "Earth Store Hall seems to be a walled garden" was a DHCP/DNS outage; routing it to `/wiki-author` on the metaphor burned a wiki probe.)
- **`/wiki-author` needs an explicit wiki signal.** Route there only when the request names a page/article, the wiki, a sitenotice, a system message, a namespace, or wiki access — not merely a graph metaphor ("orphan", "walled garden", "dead end") that could be about a network.
- **Still ambiguous after reading the whole request?** Ask one `AskUserQuestion` to disambiguate, or probe the cheaper / more likely domain first and say so — never silently commit.

## LDAP vs MediaWiki groups (recurring pitfall)

- **LDAP groups** (`cn=it,ou=Groups,dc=cttb`) govern UNIX semantics — sudo, NFS exports, polkit, login shells. → `/ldap`.
- **MediaWiki groups** (`it`, `drbu`, `dvgs`, `dvbs`, `cttb`) govern wiki Lockdown namespaces, edited via `Special:UserRights` or `plays/wiki-add-group-users.yml`. → `/wiki-author`.

"Add X to the IT group" — disambiguate first. Default reading: infra work → LDAP; documentation/wiki access → wiki. "Check the IT group on both" → split.
