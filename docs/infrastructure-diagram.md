# CTTB Core Infrastructure Diagram

> For IT personnel and system administrators. Generated 2026-04-29.
> Consumer hosts omitted; brief examples given where relevant.

---

## Network Overview

```
                            ┌──────────────────────────────────────────────────┐
                            │                  INTERNET                        │
                            └──────┬──────────────┬──────────────┬─────────────┘
                                   │              │              │
                              ┌────┴────┐   ┌────┴────┐   ┌────┴────┐
                              │  com7   │   │  com20  │   │  com10  │
                              │ wt: 10  │   │ wt: 30  │   │ wt: 30  │
                              │172.30.7 │   │172.30.20│   │172.30.10│
                              │  /24    │   │  /24    │   │  /24    │
                              └────┬────┘   └────┬────┘   └────┬────┘
                                   │              │              │
                                   │  ┌───────────┴──────────┐   │
                                   └──┤  sw-mpoe  (10.11.12  │───┘
                                      │  .30/.200)           │
                                      │  MAIN POINT OF ENTRY │
                                      └──────────┬───────────┘
                                                 │
                                                 │ fiber
                                                 │
  ┌──────────────────────────────────────────────┴──────────────────────────────────────┐
  │                                                                                     │
  │                          sw-ao-srvrm  (10.11.12.31)                                 │
  │                          SERVER ROOM SWITCH                                         │
  │                                                                                     │
  └─────┬──────────┬──────────┬──────────┬──────────┬──────────┬────────────────────────┘
        │          │          │          │          │          │
        ▼          ▼          ▼          ▼          ▼          ▼
   ┌─────────┐┌─────────┐┌─────────┐┌─────────┐┌─────────┐┌─────────┐
   │ srv-gw  ││ srv-vm  ││ srv-nas ││srv-bk-gw││srv-bk-vm││srv-bk-  │
   │ .1.1    ││ .1.3    ││ .1.5    ││ .1.9    ││ .1.7    ││ nas .11 │
   │ PRIMARY ││ PRIMARY ││ PRIMARY ││ STANDBY ││ STANDBY ││ STANDBY │
   └─────────┘└─────────┘└─────────┘└─────────┘└─────────┘└─────────┘
```

## LAN: 10.11.0.0/16

All infrastructure lives on a flat `/16`. Subnet conventions by 3rd octet:

| Octet    | Zone                     | Content Filter | Internet Schedule     |
|----------|--------------------------|----------------|-----------------------|
| `1.x`    | Infrastructure servers   | n/a            | Always on             |
| `8.x`    | Admin/Restricted         | Strict (50)    | Always on             |
| `9.x`    | DVGS (Girls School)      | IGDVS (75)     | 7:00-22:00 daily      |
| `10.x`   | DVBS (Boys School)       | IGDVS (75)     | Time-windowed*        |
| `12.x`   | Managed switches         | n/a            | n/a                   |
| `14.x`   | Student phones           | Adult (400)    | Varies                |
| `15.x`   | DRBU desktops            | Adult (400)    | Always on             |
| `19.x`   | Student laptops          | IGDVS (75)     | Varies                |
| `21-25.x`| Staff/faculty home       | Adult (400)    | Always on             |
| `31.x`   | Special services         | n/a            | Always on             |
| `43.x`   | Remote/floating          | n/a            | Always on             |

*DVBS windows: 6-10:30 & 11:30-16:30 weekdays; Community Center has separate schedule.

---

## Physical Servers (6 total, 3 active + 3 standby)

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                         srv-gw  ·  10.11.1.1                                │
│                         GATEWAY / FIREWALL                                  │
├─────────────────────────────────────────────────────────────────────────────┤
│  NIC: lan (10.11.1.1/16)  com7 (172.30.7.2)  com20 (172.30.20.2)          │
│       com10 (172.30.10.2)                                                   │
│                                                                             │
│  Services:                                                                  │
│   ├─ Firehol           Stateful firewall + timed-internet rules            │
│   ├─ Squid             Forward proxy & cache (port 8080, 4GB mem)          │
│   ├─ E2Guardian        Content filter w/ SSL MITM interception             │
│   ├─ Multi-WAN LB      Round-robin weighted: com7:10 com20:30 com10:30    │
│   └─ NTP               time.cttb (10.11.1.1)                              │
│                                                                             │
│  Static routes: Vitelity VoIP servers → com20 (SIP stability)              │
└─────────────────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────────────────┐
│                         srv-vm  ·  10.11.1.3                                │
│                         VIRTUALIZATION HOST                                 │
├─────────────────────────────────────────────────────────────────────────────┤
│  NIC: bond0 (802.3ad LACP, 4x GbE) → lxdbr0 bridge (10.11.1.3/16)        │
│                                                                             │
│  Storage: ZFS raidz2 on 4x Samsung 850 EVO 1TB SSD                        │
│           dataset: data/lxd                                                 │
│                                                                             │
│  Containers: 16 LXD (see Container Map below)                              │
│  UPS: NUT netclient → srv-nas (eaton5s)                                    │
└─────────────────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────────────────┐
│                         srv-nas  ·  10.11.1.5                               │
│                         STORAGE / NAS                                       │
├─────────────────────────────────────────────────────────────────────────────┤
│  NIC: bond0 (802.3ad LACP, 4x GbE) → lxdbr0 bridge (10.11.1.5/16)        │
│                                                                             │
│  Storage: ZFS raidz2 on 6x SAS drives + NVMe SLOG                         │
│   ├─ data/lxd         Container storage                                    │
│   ├─ data/logs        Centralized log archive (1TB quota)                  │
│   ├─ data/kvm         KVM volumes                                          │
│   └─ z_nethomes       1TB zvol → NFS home directories                      │
│                                                                             │
│  Containers: 7 LXD (see Container Map below)                               │
│  UPS: NUT master (Eaton 5S 1500VA) — srv-vm is netclient                   │
└─────────────────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────────────────┐
│  STANDBY SERVERS (currently offline)                                        │
│   srv-bk-gw  (10.11.1.9)   — Gateway replica                              │
│   srv-bk-vm  (10.11.1.7)   — VM host replica (ZFS raidz2)                 │
│   srv-bk-nas (10.11.1.11)  — NAS replica                                  │
└─────────────────────────────────────────────────────────────────────────────┘
```

---

## Container Map

All containers run Ubuntu on LXD, bridged to the LAN via `lxdbr0`.
MAC addresses encode the IP: `00:16:3e:11:01:XX` where `XX` = last octet.

### Hosted on srv-vm (10.11.1.3)

```
┌──────────────────────────────────────────────────────────────────────┐
│  srv-vm  LXD  containers                                            │
│                                                                      │
│  ┌─ AUTHENTICATION ──────────────────────────────────────────────┐   │
│  │  lxc-ldap          10.11.1.25   OpenLDAP (dc=cttb, TLS)      │   │
│  └───────────────────────────────────────────────────────────────┘   │
│                                                                      │
│  ┌─ DNS ─────────────────────────────────────────────────────────┐   │
│  │  lxc-ub-adult      10.11.1.29   Unbound — adult network      │   │
│  │  lxc-ub-igdvs      10.11.1.28   Unbound — DVGS/DVBS          │   │
│  │  lxc-dnsmasq       10.11.1.19   DNSmasq  — local cache       │   │
│  └───────────────────────────────────────────────────────────────┘   │
│                                                                      │
│  ┌─ PRINTING ────────────────────────────────────────────────────┐   │
│  │  lxc-cups-cttb     10.11.1.36   CUPS — campus-wide           │   │
│  │  lxc-cups-dvbs     10.11.1.37   CUPS — Boys School           │   │
│  │  lxc-cups-dvgs     10.11.1.38   CUPS — Girls School          │   │
│  └───────────────────────────────────────────────────────────────┘   │
│                                                                      │
│  ┌─ VOIP ────────────────────────────────────────────────────────┐   │
│  │  lxc-asterisk      10.11.1.32   Asterisk PBX + TFTP phones   │   │
│  └───────────────────────────────────────────────────────────────┘   │
│                                                                      │
│  ┌─ MONITORING ──────────────────────────────────────────────────┐   │
│  │  lxc-mon           10.11.1.26   System monitoring             │   │
│  └───────────────────────────────────────────────────────────────┘   │
│                                                                      │
│  ┌─ COLLABORATION ───────────────────────────────────────────────┐   │
│  │  lxc-wiki          10.11.1.31   Internal wiki                 │   │
│  │  lxc-blogger       10.11.1.42   Blog platform                 │   │
│  └───────────────────────────────────────────────────────────────┘   │
│                                                                      │
│  ┌─ ACCESS ──────────────────────────────────────────────────────┐   │
│  │  lxc-jumpbox       10.11.1.33   SSH bastion / admin gateway   │   │
│  └───────────────────────────────────────────────────────────────┘   │
│                                                                      │
│  ┌─ APPLICATIONS ────────────────────────────────────────────────┐   │
│  │  lxc-sltp          10.11.1.39   Sanskrit Learning Platform    │   │
│  │  lxc-sltp-git      10.11.1.40   SLTP Git backend              │   │
│  │  lxc-drbu-sis      10.11.1.41   DRBU Student Info System      │   │
│  └───────────────────────────────────────────────────────────────┘   │
│                                                                      │
└──────────────────────────────────────────────────────────────────────┘
```

### Hosted on srv-nas (10.11.1.5)

```
┌──────────────────────────────────────────────────────────────────────┐
│  srv-nas  LXD  containers                                            │
│                                                                      │
│  ┌─ STORAGE ─────────────────────────────────────────────────────┐   │
│  │  lxc-fs            10.11.1.18   NFS server (nethomes zvol)    │   │
│  │                                  privileged, rpc_pipefs/nfsd   │   │
│  └───────────────────────────────────────────────────────────────┘   │
│                                                                      │
│  ┌─ LOGGING ─────────────────────────────────────────────────────┐   │
│  │  lxc-log           10.11.1.20   Syslog (/data/logs mount)    │   │
│  └───────────────────────────────────────────────────────────────┘   │
│                                                                      │
│  ┌─ SOURCE CONTROL ──────────────────────────────────────────────┐   │
│  │  lxc-git           10.11.1.21   Git server                    │   │
│  └───────────────────────────────────────────────────────────────┘   │
│                                                                      │
│  ┌─ DEPLOYMENT ──────────────────────────────────────────────────┐   │
│  │  lxc-debmirror     10.11.1.22   Apt mirror (apt.cttb)        │   │
│  │  lxc-pxe           10.11.1.23   PXE: TFTP + Apache preseed   │   │
│  └───────────────────────────────────────────────────────────────┘   │
│                                                                      │
│  ┌─ MONITORING ──────────────────────────────────────────────────┐   │
│  │  lxc-metrics       10.11.1.24   Metrics collection            │   │
│  └───────────────────────────────────────────────────────────────┘   │
│                                                                      │
│  ┌─ LIBRARY ─────────────────────────────────────────────────────┐   │
│  │  lxc-koha          10.11.1.27   Koha library system           │   │
│  │                                  library.igdvs.cttb            │   │
│  └───────────────────────────────────────────────────────────────┘   │
│                                                                      │
└──────────────────────────────────────────────────────────────────────┘
```

---

## Service Dependency Map

```
                    ┌─────────────┐
                    │  INTERNET   │
                    └──────┬──────┘
                           │
                    ┌──────▼──────┐
                    │   srv-gw    │
                    │  Firehol    │
                    │  Squid+E2G  │
                    │  Multi-WAN  │
                    │  NTP        │
                    └──┬───┬───┬──┘
                       │   │   │
          ┌────────────┘   │   └────────────┐
          ▼                ▼                ▼
   ┌──────────────┐ ┌──────────────┐ ┌──────────────┐
   │  DNS          │ │  DHCP        │ │  Content     │
   │              │ │  (srv-gw or  │ │  Filtering   │
   │ lxc-ub-adult│ │   external)  │ │  E2Guardian  │
   │ lxc-ub-igdvs│ │              │ │  4 groups:   │
   │ lxc-dnsmasq │ │              │ │  adult/nbyp/ │
   │              │ │              │ │  restricted/ │
   │ zone: .cttb │ │              │ │  igdvs       │
   └──────┬───────┘ └──────┬───────┘ └──────────────┘
          │                │
          │    ┌───────────┘
          ▼    ▼
   ┌──────────────┐       ┌──────────────┐      ┌──────────────┐
   │  PXE BOOT    │       │  AUTH         │      │  FILE STORE  │
   │              │       │              │      │              │
   │ lxc-pxe     │       │ lxc-ldap     │      │ lxc-fs       │
   │ TFTP+Apache │       │ OpenLDAP     │      │ NFS /nethomes│
   │ preseed auto│       │ dc=cttb, TLS │      │              │
   │              │       │              │      │              │
   │ NEEDS:      │       │ NEEDED BY:   │      │ NEEDED BY:   │
   │  DHCP, DNS, │       │  all clients │      │  all clients │
   │  debmirror  │       │  (login)     │      │  (home dirs) │
   └──────┬───────┘       └──────────────┘      └──────────────┘
          │
          ▼
   ┌──────────────┐
   │  APT MIRROR  │
   │              │
   │ lxc-debmirror│
   │ apt.cttb     │
   │              │
   │ Ubuntu, Koha,│
   │ VBox repos   │
   └──────────────┘
```

### Client Boot & Login Flow

```
  ┌──────────────┐
  │  NEW CLIENT  │  (e.g. dvgs-lab3-pc1)
  └──────┬───────┘
         │ 1. PXE ROM
         ▼
  ┌──────────────┐  DHCP OFFER: IP + next-server=10.11.1.23
  │  DHCP Server │──────────────────────────────────────────┐
  └──────────────┘                                          │
         │ 2. TFTP download                                 │
         ▼                                                  ▼
  ┌──────────────┐  lpxelinux.0 → menu     ┌──────────────┐
  │  lxc-pxe     │────────────────────────→│  Boot Menu    │
  │  TFTP+Apache │                         │  default      │
  └──────────────┘                         │  server-raid1 │
         │ 3. Preseed install              │  server-raid6 │
         │    apt from debmirror           │  desktop      │
         ▼                                 └───────────────┘
  ┌──────────────┐
  │  INSTALLED   │
  │  CLIENT      │
  └──────┬───────┘
         │ 4. First boot
         ▼
  ┌──────────────────────────────────────────────────────────┐
  │  Client connects to core services:                       │
  │                                                          │
  │   DNS ─────→ lxc-ub-adult (10.11.1.29)                  │
  │              or lxc-ub-igdvs (10.11.1.28)                │
  │                                                          │
  │   AUTH ────→ lxc-ldap (ldap.cttb / 10.11.1.25)          │
  │                                                          │
  │   HOME ────→ lxc-fs (nfs.cttb / 10.11.1.18)             │
  │              mount /nethomes via NFS                      │
  │                                                          │
  │   PRINT ───→ lxc-cups-{cttb,dvbs,dvgs}                  │
  │              (.1.36 / .1.37 / .1.38)                     │
  │                                                          │
  │   WEB ─────→ srv-gw:8080 (Squid → E2Guardian → internet)│
  │                                                          │
  │   TIME ────→ ntp.cttb (10.11.1.1)                       │
  │                                                          │
  │   SYSLOG ──→ lxc-log (10.11.1.20)                       │
  └──────────────────────────────────────────────────────────┘
```

---

## DNS Zone Summary (.cttb)

Core service records resolved by Unbound:

| Record             | IP            | Service                    |
|--------------------|---------------|----------------------------|
| `gw.cttb`          | 10.11.1.1     | Gateway / firewall / NTP   |
| `srv-vm.cttb`      | 10.11.1.3     | VM host                    |
| `srv-nas.cttb`     | 10.11.1.5     | NAS                        |
| `fileserver.cttb`  | 10.11.1.18    | NFS home directories       |
| `nfs.cttb`         | 10.11.1.18    | NFS (alias)                |
| `dnsmasq.cttb`     | 10.11.1.19    | DNS cache                  |
| `log-srv.cttb`     | 10.11.1.20    | Centralized syslog         |
| `git.cttb`         | 10.11.1.21    | Git server                 |
| `apt.cttb`         | 10.11.1.22    | Apt mirror (debmirror)     |
| `pxe.cttb`         | 10.11.1.23    | PXE / TFTP / preseed       |
| `ldap.cttb`        | 10.11.1.25    | OpenLDAP directory         |
| `mon.cttb`         | 10.11.1.26    | Monitoring                 |
| `library.igdvs.cttb`| 10.11.1.27   | Koha library system        |
| `ub-igdvs.cttb`    | 10.11.1.28    | Unbound DNS (schools)      |
| `ub-adult.cttb`    | 10.11.1.29    | Unbound DNS (adult)        |
| `wiki.cttb`        | 10.11.1.31    | Internal wiki              |
| `asterisk.cttb`    | 10.11.1.32    | VoIP PBX                   |
| `cups-cttb.cttb`   | 10.11.1.36    | Print server (campus)      |
| `lxc-sltp.cttb`    | 10.11.1.39    | Sanskrit platform           |
| `sis.drbu.cttb`    | 10.11.1.41    | Student info system        |
| `blogger.cttb`     | 10.11.1.42    | Blog                       |
| `dns1.cttb`        | 10.11.31.131  | External DNS forwarder     |
| `time.cttb`        | 10.11.1.1     | NTP (alias for gw)         |

---

## UPS Power Chain

```
  ┌──────────────────────┐
  │  Eaton 5S 1500VA     │
  │  (physical UPS)      │
  └──────────┬───────────┘
             │
     ┌───────▼────────┐
     │  srv-nas        │  NUT master
     │  upsmon master  │
     └───────┬─────────┘
             │ NUT netclient
     ┌───────▼────────┐
     │  srv-vm         │  NUT slave
     │  upsmon slave   │  → orderly LXD shutdown
     └────────────────┘
```

---

## Campus Network — Switch Fabric (10.11.12.x)

80+ managed switches across campus. Key aggregation points:

```
                        ┌────────────────┐
                        │  sw-mpoe       │  Main Point of Entry
                        │  10.11.12.30   │  (WAN uplinks)
                        └───────┬────────┘
                                │
               ┌────────────────┼────────────────┐
               ▼                ▼                ▼
        ┌────────────┐  ┌────────────┐   ┌────────────┐
        │ sw-ao-srvrm│  │ sw-tob-    │   │ sw-drbu-   │
        │ Server Room│  │ center     │   │ downstairs │
        │ .12.31     │  │ .12.34     │   │ .12.36     │
        └─────┬──────┘  └─────┬──────┘   └─────┬──────┘
              │               │                 │
     ┌────┬──┴──┬────┐  ┌───┴───┐    ┌────┬──┴──┬─────┐
     ▼    ▼     ▼    ▼  ▼       ▼    ▼    ▼     ▼     ▼
   DVGS  DVBS  1234  AO ToB   JGH  DRBU  DRBU  DRBU  DRBU
   wing  wing  bldg  AO labs  dorm  lib   cs    cdorm upst
```

Buildings include: DVGS, DVBS, DRBU, 1234, Tower of Bliss (ToB),
Administration Office (AO), Joyous Giving House (JGH), and more.

---

## Access & Credentials

| Target        | Method               | User            | Auth           |
|---------------|----------------------|-----------------|----------------|
| Jumpbox       | `ssh cttb`           | administrator   | password       |
| srv-gw        | `ssh administrator@10.11.1.1` | administrator | pubkey only |
| srv-vm        | `ssh administrator@10.11.1.3` | administrator | pubkey only |
| srv-nas       | `ssh administrator@10.11.1.5` | administrator | pubkey only |
| Containers    | `lxc exec <name> bash` (from host) | root  | n/a (LXD)     |
| Switches      | SNMP / web / SSH     | varies          | per-device     |

Password-capable hosts share: `administrator` / `4m1t0f0` (with sudo).
Infrastructure servers (srv-*) require SSH pubkey — deploy via Ansible.

---

## Quick Reference: "What runs where?"

| Need to...                  | Go to                          | IP           |
|-----------------------------|--------------------------------|--------------|
| Debug internet/firewall     | srv-gw                         | 10.11.1.1    |
| Manage containers           | srv-vm or srv-nas (LXD)        | .1.3 / .1.5  |
| Reset a user password       | lxc-ldap                       | 10.11.1.25   |
| Fix DNS resolution          | lxc-ub-adult or lxc-ub-igdvs  | .1.29 / .1.28|
| Fix printing                | lxc-cups-{cttb,dvbs,dvgs}      | .1.36-38     |
| PXE boot a new machine      | lxc-pxe                        | 10.11.1.23   |
| Check home dir mounts       | lxc-fs (NFS on srv-nas)        | 10.11.1.18   |
| Read centralized logs       | lxc-log                        | 10.11.1.20   |
| Update packages/mirrors     | lxc-debmirror                  | 10.11.1.22   |
| Phone system / VoIP         | lxc-asterisk                   | 10.11.1.32   |
| Library catalog (Koha)      | lxc-koha                       | 10.11.1.27   |
| Monitoring / metrics        | lxc-mon / lxc-metrics          | .1.26 / .1.24|
| Git repos                   | lxc-git                        | 10.11.1.21   |
| SSH into campus from outside| lxc-jumpbox                    | 10.11.1.33   |
