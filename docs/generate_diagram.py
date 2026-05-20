#!/usr/bin/env python3
"""Generate CTTB Infrastructure wall poster PDF.

Single large-format page with spatial/geometric layout showing
physical topology, service relationships, and data flow.
Designed to be printed large and mounted on a wall.
"""

import matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt
from matplotlib.patches import FancyBboxPatch
import matplotlib.patheffects as pe
import numpy as np
import os
from matplotlib.backends.backend_pdf import PdfPages

# ── Global font scale ─────────────────────────────────────────
# All font sizes are multiplied by this. Increase for larger print.
FS = 1.6

# ── Color Palette ──────────────────────────────────────────────
C = {
    'bg':           '#0f1120',
    'bg2':          '#151830',
    'grid':         '#1a1f3a',
    'grid_accent':  '#252b50',
    'wan':          '#ff4d6a',
    'wan_glow':     '#ff4d6a30',
    'gw':           '#ff6b35',
    'gw_fill':      '#2a1508',
    'gw_glow':      '#ff6b3520',
    'vm':           '#00b4d8',
    'vm_fill':      '#041e28',
    'vm_glow':      '#00b4d820',
    'nas':          '#00c896',
    'nas_fill':     '#04281e',
    'nas_glow':     '#00c89620',
    'standby':      '#4a5568',
    'sb_fill':      '#1a1f2e',
    'dns':          '#22d3ee',
    'dns_fill':     '#062830',
    'auth':         '#fbbf24',
    'auth_fill':    '#302808',
    'print':        '#f472b6',
    'print_fill':   '#300820',
    'storage':      '#34d399',
    'stor_fill':    '#083020',
    'deploy':       '#fb923c',
    'dep_fill':     '#301808',
    'voip':         '#a78bfa',
    'voip_fill':    '#180830',
    'monitor':      '#2dd4bf',
    'mon_fill':     '#082820',
    'log':          '#a3e635',
    'log_fill':     '#182808',
    'app':          '#818cf8',
    'app_fill':     '#101840',
    'library':      '#e879f9',
    'lib_fill':     '#280830',
    'collab':       '#67e8f9',
    'col_fill':     '#082830',
    'zone_dvgs':    '#f472b6',
    'zone_dvbs':    '#60a5fa',
    'zone_drbu':    '#a78bfa',
    'zone_admin':   '#fbbf24',
    'zone_infra':   '#00b4d8',
    'switch':       '#fbbf24',
    'sw_fill':      '#282008',
    'text':         '#cbd5e1',
    'text_dim':     '#64748b',
    'text_bright':  '#f1f5f9',
    'white':        '#ffffff',
}

# ── Helpers ────────────────────────────────────────────────────

def glow_box(ax, x, y, w, h, edge_color, fill_color, glow_color=None,
             label='', sublabel='', fontsize=9, lw=2, radius=0.006,
             zorder=5, sublabel_color=None):
    if glow_color:
        g = FancyBboxPatch((x-0.002, y-0.002), w+0.004, h+0.004,
                           boxstyle=f"round,pad=0,rounding_size={radius+0.002}",
                           facecolor=glow_color, edgecolor='none',
                           alpha=0.35, zorder=zorder-1)
        ax.add_patch(g)
    box = FancyBboxPatch((x, y), w, h,
                         boxstyle=f"round,pad=0,rounding_size={radius}",
                         facecolor=fill_color, edgecolor=edge_color,
                         linewidth=lw, alpha=0.95, zorder=zorder)
    ax.add_patch(box)
    if label:
        ly = y + h/2 + (0.003 if sublabel else 0)
        ax.text(x + w/2, ly, label, ha='center', va='center',
                fontsize=fontsize * FS, fontweight='bold', color=edge_color,
                zorder=zorder+1)
    if sublabel:
        ax.text(x + w/2, y + h/2 - 0.005, sublabel,
                ha='center', va='center', fontsize=(fontsize - 2) * FS,
                color=sublabel_color or C['text_dim'], zorder=zorder+1)


def pipe(ax, x1, y1, x2, y2, color, lw=2.5, zorder=3):
    ax.plot([x1, x2], [y1, y2], color=color, lw=lw, solid_capstyle='round',
            alpha=0.45, zorder=zorder)
    ax.plot([x1, x2], [y1, y2], color=color, lw=lw*0.35, solid_capstyle='round',
            alpha=0.85, zorder=zorder+1)


def section_label(ax, x, y, text, color, fontsize=11):
    ax.text(x, y, text, fontsize=fontsize * FS, fontweight='bold',
            color=color, va='bottom', zorder=20,
            fontfamily='monospace',
            path_effects=[pe.withStroke(linewidth=4, foreground=C['bg'])])
    ax.plot([x, x + len(text)*0.0055], [y - 0.002, y - 0.002],
            color=color, lw=2.5, zorder=20, alpha=0.5)


def draw_container_group(ax, gx, gy, gw, group_name, containers, gcolor, gfill):
    row_h = 0.016
    gh = 0.012 + len(containers) * row_h
    glow_box(ax, gx, gy - gh, gw, gh, gcolor, gfill, None,
             radius=0.004, lw=1.2)
    ax.text(gx + 0.006, gy - 0.004, group_name,
            fontsize=8 * FS, fontweight='bold', color=gcolor, zorder=10,
            fontfamily='monospace')
    for i, (cname, cip, cdesc) in enumerate(containers):
        cy = gy - 0.014 - i * row_h
        ax.plot(gx + 0.008, cy + 0.003, 'o', color=gcolor,
                markersize=4.5, zorder=10)
        ax.text(gx + 0.016, cy + 0.003, cname,
                fontsize=8.5 * FS, fontweight='bold', color=gcolor,
                zorder=10, fontfamily='monospace', va='center')
        ax.text(gx + 0.11, cy + 0.003, cip,
                fontsize=7.5 * FS, color=C['text_dim'],
                zorder=10, fontfamily='monospace', va='center')
        ax.text(gx + 0.155, cy + 0.003, cdesc,
                fontsize=8 * FS, color=C['text'], zorder=10, va='center')
    return gh


# ══════════════════════════════════════════════════════════════
# POSTER
# ══════════════════════════════════════════════════════════════
def draw_poster():
    fig, ax = plt.subplots(1, 1, figsize=(34, 52))
    fig.patch.set_facecolor(C['bg'])
    ax.set_facecolor(C['bg'])
    ax.set_xlim(0, 1)
    ax.set_ylim(0, 1)
    ax.axis('off')

    # Grid
    for i in range(0, 100, 2):
        v = i / 100
        ax.axhline(v, color=C['grid'], lw=0.2, zorder=0)
        ax.axvline(v, color=C['grid'], lw=0.2, zorder=0)
    for i in range(0, 100, 10):
        v = i / 100
        ax.axhline(v, color=C['grid_accent'], lw=0.4, zorder=0)
        ax.axvline(v, color=C['grid_accent'], lw=0.4, zorder=0)

    # ── TITLE ──
    ax.text(0.50, 0.988, 'CTTB NETWORK INFRASTRUCTURE',
            ha='center', va='top', fontsize=48 * FS, fontweight='bold',
            color=C['white'], zorder=20, fontfamily='monospace',
            path_effects=[pe.withStroke(linewidth=5, foreground=C['bg'])])
    ax.text(0.50, 0.976, 'City of Ten Thousand Buddhas  \u2502  Core Services & Physical Topology',
            ha='center', va='top', fontsize=14 * FS, color=C['text_dim'], zorder=20)
    ax.text(0.50, 0.970, 'LAN 10.11.0.0/16  \u2502  DNS .cttb  \u2502  Proxy srv-gw:8080  \u2502  2026-04-29',
            ha='center', va='top', fontsize=11 * FS, color=C['text_dim'], zorder=20,
            fontfamily='monospace')

    # ════════════════════════════════════════════════════════════
    # LAYER 1: WAN
    # ════════════════════════════════════════════════════════════
    section_label(ax, 0.03, 0.958, 'LAYER 1 \u2502 WAN UPLINKS', C['wan'])

    inet_y = 0.948
    ax.text(0.50, inet_y, '\u2601  INTERNET',
            ha='center', va='center', fontsize=24 * FS, fontweight='bold',
            color=C['wan'], zorder=10,
            path_effects=[pe.withStroke(linewidth=4, foreground=C['bg'])])

    wan_y = 0.920
    wans = [
        ('com7',  '172.30.7.2/24',  'ISP #1  wt:10', 0.20),
        ('com20', '172.30.20.2/24', 'ISP #2  wt:30', 0.50),
        ('com10', '172.30.10.2/24', 'ISP #3  wt:30', 0.80),
    ]
    for name, ip, desc, cx in wans:
        glow_box(ax, cx-0.11, wan_y, 0.22, 0.020,
                 C['wan'], C['bg2'], C['wan_glow'],
                 f'{name}  ({ip})', desc, fontsize=10, radius=0.005)
        pipe(ax, cx, inet_y - 0.008, cx, wan_y + 0.020, C['wan'], lw=3.5)

    # ════════════════════════════════════════════════════════════
    # LAYER 2: EDGE
    # ════════════════════════════════════════════════════════════
    section_label(ax, 0.03, 0.912, 'LAYER 2 \u2502 NETWORK EDGE', C['gw'])

    # MPOE
    mpoe_y = 0.893
    glow_box(ax, 0.25, mpoe_y, 0.50, 0.016,
             C['switch'], C['sw_fill'], None,
             'sw-mpoe  \u2502  10.11.12.30  \u2502  Main Point of Entry',
             fontsize=9, radius=0.005)
    for cx in [0.20, 0.50, 0.80]:
        pipe(ax, cx, wan_y, 0.50, mpoe_y + 0.016, C['switch'], lw=2.5)

    # Gateway
    gw_y = 0.855
    gw_h = 0.032
    glow_box(ax, 0.08, gw_y, 0.84, gw_h,
             C['gw'], C['gw_fill'], C['gw_glow'], radius=0.008, lw=3)
    ax.text(0.50, gw_y + gw_h - 0.005, 'srv-gw',
            ha='center', fontsize=24 * FS, fontweight='bold', color=C['gw'],
            zorder=10, fontfamily='monospace')
    ax.text(0.50, gw_y + gw_h - 0.016, '10.11.1.1  \u2502  GATEWAY / FIREWALL',
            ha='center', fontsize=10 * FS, color=C['text_dim'], zorder=10)
    pipe(ax, 0.50, mpoe_y, 0.50, gw_y + gw_h, C['gw'], lw=4)

    # Gateway service badges
    gw_svcs = [
        ('FIREHOL',       'Stateful firewall + timed internet'),
        ('SQUID',         'Forward proxy & cache on :8080'),
        ('E2GUARDIAN',    'Content filter with SSL MITM'),
        ('MULTI-WAN LB', 'Round-robin 10/30/30 weighted'),
        ('NTP',           'time.cttb for all clients'),
    ]
    badge_y = gw_y - 0.022
    badge_w = 0.175
    badge_gap = (0.84 - 5 * badge_w) / 4
    bx = 0.08
    for sname, sdesc in gw_svcs:
        glow_box(ax, bx, badge_y, badge_w, 0.018,
                 C['gw'], '#1a0d05', None,
                 f'{sname}', sdesc,
                 fontsize=7.5, lw=1.2, radius=0.004)
        pipe(ax, bx + badge_w/2, gw_y, bx + badge_w/2, badge_y + 0.018, C['gw'], lw=1)
        bx += badge_w + badge_gap

    # ════════════════════════════════════════════════════════════
    # LAYER 3: SERVER ROOM
    # ════════════════════════════════════════════════════════════
    section_label(ax, 0.03, 0.822, 'LAYER 3 \u2502 SERVER ROOM', C['vm'])

    # Server room switch
    sr_y = 0.808
    glow_box(ax, 0.06, sr_y, 0.88, 0.012,
             C['switch'], C['sw_fill'], None,
             'sw-ao-srvrm  \u2502  10.11.12.31  \u2502  Server Room Aggregation Switch',
             fontsize=8.5, radius=0.004)
    pipe(ax, 0.50, badge_y, 0.50, sr_y + 0.012, C['switch'], lw=3)

    # ── Physical Servers ──
    phys_y = 0.745
    phys_h = 0.055

    # srv-vm
    vm_x, vm_w = 0.03, 0.30
    glow_box(ax, vm_x, phys_y, vm_w, phys_h,
             C['vm'], C['vm_fill'], C['vm_glow'], radius=0.006, lw=2.5)
    ax.text(vm_x + vm_w/2, phys_y + phys_h - 0.006, 'srv-vm',
            ha='center', fontsize=20 * FS, fontweight='bold', color=C['vm'],
            zorder=10, fontfamily='monospace')
    ax.text(vm_x + vm_w/2, phys_y + phys_h - 0.018, '10.11.1.3  \u2502  VIRTUALIZATION HOST',
            ha='center', fontsize=8 * FS, color=C['text_dim'], zorder=10)
    for i, d in enumerate([
        '16 LXD containers on ZFS',
        'bond0: 802.3ad LACP 4\u00d7GbE \u2192 lxdbr0',
        'ZFS raidz2: 4\u00d7 Samsung 850 EVO 1TB',
        'NUT netclient (UPS slave \u2192 srv-nas)',
    ]):
        ax.text(vm_x + 0.012, phys_y + phys_h - 0.028 - i*0.008, f'\u25b8 {d}',
                fontsize=7 * FS, color=C['text'], zorder=10)
    pipe(ax, vm_x + vm_w/2, sr_y, vm_x + vm_w/2, phys_y + phys_h, C['vm'], lw=3)

    # srv-nas
    nas_x, nas_w = 0.35, 0.30
    glow_box(ax, nas_x, phys_y, nas_w, phys_h,
             C['nas'], C['nas_fill'], C['nas_glow'], radius=0.006, lw=2.5)
    ax.text(nas_x + nas_w/2, phys_y + phys_h - 0.006, 'srv-nas',
            ha='center', fontsize=20 * FS, fontweight='bold', color=C['nas'],
            zorder=10, fontfamily='monospace')
    ax.text(nas_x + nas_w/2, phys_y + phys_h - 0.018, '10.11.1.5  \u2502  NETWORK STORAGE',
            ha='center', fontsize=8 * FS, color=C['text_dim'], zorder=10)
    for i, d in enumerate([
        '7 LXD containers on ZFS',
        'bond0: 802.3ad LACP 4\u00d7GbE \u2192 lxdbr0',
        'ZFS raidz2: 6\u00d7SAS + NVMe SLOG',
        'NUT master: Eaton 5S 1500VA UPS',
        'Datasets: lxd, logs(1T), kvm, nethomes(1T)',
    ]):
        ax.text(nas_x + 0.012, phys_y + phys_h - 0.028 - i*0.008, f'\u25b8 {d}',
                fontsize=7 * FS, color=C['text'], zorder=10)
    pipe(ax, nas_x + nas_w/2, sr_y, nas_x + nas_w/2, phys_y + phys_h, C['nas'], lw=3)

    # Standby
    sb_x, sb_w = 0.67, 0.30
    glow_box(ax, sb_x, phys_y, sb_w, phys_h,
             C['standby'], C['sb_fill'], None, radius=0.006, lw=1.5)
    ax.text(sb_x + sb_w/2, phys_y + phys_h - 0.006, 'STANDBY REPLICAS',
            ha='center', fontsize=14 * FS, fontweight='bold', color=C['standby'],
            zorder=10, fontfamily='monospace')
    ax.text(sb_x + sb_w/2, phys_y + phys_h - 0.018, 'Currently offline',
            ha='center', fontsize=8 * FS, color=C['text_dim'], zorder=10)
    for i, (n, ip, desc) in enumerate([
        ('srv-bk-gw',  '10.11.1.9',  'Gateway replica'),
        ('srv-bk-vm',  '10.11.1.7',  'VM host replica (ZFS raidz2)'),
        ('srv-bk-nas', '10.11.1.11', 'NAS replica'),
    ]):
        ax.text(sb_x + 0.012, phys_y + phys_h - 0.030 - i*0.010,
                f'\u25b8 {n}', fontsize=8 * FS, fontweight='bold',
                color=C['standby'], zorder=10, fontfamily='monospace')
        ax.text(sb_x + 0.110, phys_y + phys_h - 0.030 - i*0.010,
                f'{ip}  \u2014  {desc}', fontsize=7.5 * FS, color=C['text_dim'], zorder=10)
    pipe(ax, sb_x + sb_w/2, sr_y, sb_x + sb_w/2, phys_y + phys_h, C['standby'], lw=2)

    # UPS arrow
    ups_cx = (vm_x + vm_w + nas_x) / 2
    ax.annotate('', xy=(vm_x + vm_w, phys_y + 0.008),
                xytext=(nas_x, phys_y + 0.008),
                arrowprops=dict(arrowstyle='<->', color=C['nas'], lw=2),
                zorder=10)
    ax.text(ups_cx, phys_y + 0.002, 'NUT master\u2192slave',
            ha='center', fontsize=7 * FS, color=C['nas'], zorder=10,
            fontfamily='monospace',
            bbox=dict(boxstyle='round,pad=0.15', facecolor=C['bg'], edgecolor='none'))

    # ════════════════════════════════════════════════════════════
    # LAYER 4: CONTAINERS
    # ════════════════════════════════════════════════════════════
    section_label(ax, 0.03, 0.735, 'LAYER 4 \u2502 CORE SERVICES  (LXD containers, bridged via lxdbr0)', C['vm'])

    # ── srv-vm container panel ──
    vm_panel_y = 0.460
    vm_panel_h = 0.268
    glow_box(ax, 0.03, vm_panel_y, 0.46, vm_panel_h,
             C['vm'], C['vm_fill'], None, radius=0.006, lw=1.5)
    ax.text(0.26, vm_panel_y + vm_panel_h - 0.005,
            'srv-vm CONTAINERS (10.11.1.3)',
            ha='center', fontsize=12 * FS, fontweight='bold', color=C['vm'],
            zorder=10, fontfamily='monospace')
    pipe(ax, vm_x + vm_w/2, phys_y, 0.26, vm_panel_y + vm_panel_h, C['vm'], lw=3)

    # Left column
    lcx = 0.04
    lcw = 0.215
    lcy = vm_panel_y + vm_panel_h - 0.022

    h = draw_container_group(ax, lcx, lcy, lcw, 'AUTHENTICATION',
        [('lxc-ldap', '.1.25', 'OpenLDAP dc=cttb TLS')],
        C['auth'], C['auth_fill'])
    lcy -= h + 0.007

    h = draw_container_group(ax, lcx, lcy, lcw, 'DNS',
        [('lxc-ub-adult', '.1.29', 'Unbound (adult)'),
         ('lxc-ub-igdvs', '.1.28', 'Unbound (schools)'),
         ('lxc-dnsmasq',  '.1.19', 'DNSmasq cache')],
        C['dns'], C['dns_fill'])
    lcy -= h + 0.007

    h = draw_container_group(ax, lcx, lcy, lcw, 'PRINTING',
        [('lxc-cups-cttb', '.1.36', 'Campus-wide'),
         ('lxc-cups-dvbs', '.1.37', 'Boys School'),
         ('lxc-cups-dvgs', '.1.38', 'Girls School')],
        C['print'], C['print_fill'])
    lcy -= h + 0.007

    h = draw_container_group(ax, lcx, lcy, lcw, 'VOIP',
        [('lxc-asterisk', '.1.32', 'PBX + TFTP phones')],
        C['voip'], C['voip_fill'])

    # Right column
    rcx = 0.265
    rcw = 0.215
    rcy = vm_panel_y + vm_panel_h - 0.022

    h = draw_container_group(ax, rcx, rcy, rcw, 'MONITORING',
        [('lxc-mon', '.1.26', 'System monitoring')],
        C['monitor'], C['mon_fill'])
    rcy -= h + 0.007

    h = draw_container_group(ax, rcx, rcy, rcw, 'COLLABORATION',
        [('lxc-wiki',    '.1.31', 'Internal wiki'),
         ('lxc-blogger', '.1.42', 'Blog platform')],
        C['collab'], C['col_fill'])
    rcy -= h + 0.007

    h = draw_container_group(ax, rcx, rcy, rcw, 'SSH ACCESS',
        [('lxc-jumpbox', '.1.33', 'Bastion / admin gw')],
        C['gw'], C['gw_fill'])
    rcy -= h + 0.007

    h = draw_container_group(ax, rcx, rcy, rcw, 'APPLICATIONS',
        [('lxc-sltp',     '.1.39', 'Sanskrit platform'),
         ('lxc-sltp-git', '.1.40', 'SLTP Git backend'),
         ('lxc-drbu-sis', '.1.41', 'DRBU Student Info')],
        C['app'], C['app_fill'])

    # ── srv-nas container panel ──
    glow_box(ax, 0.51, vm_panel_y, 0.46, vm_panel_h,
             C['nas'], C['nas_fill'], None, radius=0.006, lw=1.5)
    ax.text(0.74, vm_panel_y + vm_panel_h - 0.005,
            'srv-nas CONTAINERS (10.11.1.5)',
            ha='center', fontsize=12 * FS, fontweight='bold', color=C['nas'],
            zorder=10, fontfamily='monospace')
    pipe(ax, nas_x + nas_w/2, phys_y, 0.74, vm_panel_y + vm_panel_h, C['nas'], lw=3)

    ncx = 0.52
    ncw = 0.44
    ncy = vm_panel_y + vm_panel_h - 0.022

    h = draw_container_group(ax, ncx, ncy, ncw, 'FILE STORAGE',
        [('lxc-fs', '.1.18', 'NFS /nethomes (1TB zvol, privileged)')],
        C['storage'], C['stor_fill'])
    ncy -= h + 0.007

    h = draw_container_group(ax, ncx, ncy, ncw, 'CENTRALIZED LOGGING',
        [('lxc-log', '.1.20', 'Syslog (bind-mount /data/logs, 1TB)')],
        C['log'], C['log_fill'])
    ncy -= h + 0.007

    h = draw_container_group(ax, ncx, ncy, ncw, 'SOURCE CONTROL',
        [('lxc-git', '.1.21', 'Git server')],
        C['app'], C['app_fill'])
    ncy -= h + 0.007

    h = draw_container_group(ax, ncx, ncy, ncw, 'DEPLOYMENT PIPELINE',
        [('lxc-debmirror', '.1.22', 'Apt mirror (Ubuntu, Koha, VBox)'),
         ('lxc-pxe',       '.1.23', 'PXE: TFTP + Apache preseed')],
        C['deploy'], C['dep_fill'])
    ncy -= h + 0.007

    h = draw_container_group(ax, ncx, ncy, ncw, 'METRICS',
        [('lxc-metrics', '.1.24', 'Metrics collection')],
        C['monitor'], C['mon_fill'])
    ncy -= h + 0.007

    h = draw_container_group(ax, ncx, ncy, ncw, 'LIBRARY SYSTEM',
        [('lxc-koha', '.1.27', 'Koha ILS (library.igdvs.cttb)')],
        C['library'], C['lib_fill'])

    # ════════════════════════════════════════════════════════════
    # DATA FLOW: Client lifecycle
    # ════════════════════════════════════════════════════════════
    section_label(ax, 0.03, 0.450, 'CLIENT LIFECYCLE', C['deploy'])

    # PXE boot pipeline
    flow_y = 0.428
    steps = [
        ('\u2460 PXE ROM',     'Client powers on',   C['text']),
        ('\u2461 DHCP',        'IP + next-server',    C['dns']),
        ('\u2462 lxc-pxe',     'TFTP lpxelinux.0',   C['deploy']),
        ('\u2463 Boot Menu',   'default / raid1/6',   C['deploy']),
        ('\u2464 Preseed',     'apt.cttb autoinstall', C['deploy']),
        ('\u2465 READY',       'Client joins LAN',    C['vm']),
    ]
    step_w = 0.135
    gap = (0.94 - 6 * step_w) / 5
    sx = 0.03
    for label, desc, color in steps:
        glow_box(ax, sx, flow_y, step_w, 0.018,
                 color, C['bg2'], None,
                 label, desc, fontsize=8, radius=0.004, lw=1.5)
        sx += step_w + gap
    # Arrows
    sx = 0.03
    for i in range(5):
        x1 = sx + step_w
        x2 = x1 + gap
        ax.annotate('', xy=(x2, flow_y + 0.009), xytext=(x1, flow_y + 0.009),
                    arrowprops=dict(arrowstyle='->', color=C['deploy'], lw=2.5,
                                   shrinkA=1, shrinkB=1),
                    zorder=10)
        sx += step_w + gap

    # Post-boot services
    ax.text(0.50, flow_y - 0.009, '\u25bc  Running client connects to these services:',
            ha='center', fontsize=8 * FS, color=C['text_dim'], zorder=10,
            fontfamily='monospace')

    svc_y = flow_y - 0.032
    svcs = [
        ('DNS',     '.1.29/.28',  'Unbound',     C['dns']),
        ('AUTH',    '.1.25',      'LDAP login',   C['auth']),
        ('HOME',    '.1.18',      'NFS mount',    C['storage']),
        ('PRINT',   '.1.36-38',   'CUPS',         C['print']),
        ('WEB',     'gw:8080',    'Squid+E2G',    C['gw']),
        ('SYSLOG',  '.1.20',      'Centralized',  C['log']),
        ('TIME',    '.1.1',       'NTP',          C['text']),
    ]
    svc_w = 0.12
    sgap = (0.94 - 7 * svc_w) / 6
    sx = 0.03
    for sname, sip, sdesc, scolor in svcs:
        glow_box(ax, sx, svc_y, svc_w, 0.022,
                 scolor, C['bg2'], None,
                 sname, f'{sip}  {sdesc}',
                 fontsize=8, radius=0.004, lw=1.5)
        sx += svc_w + sgap

    # ════════════════════════════════════════════════════════════
    # NETWORK ZONES
    # ════════════════════════════════════════════════════════════
    section_label(ax, 0.03, 0.375, 'LAYER 5 \u2502 NETWORK ZONES  (subnets within 10.11.0.0/16)', C['zone_dvgs'])

    # Infrastructure
    tier_y = 0.348
    glow_box(ax, 0.03, tier_y, 0.94, 0.022,
             C['zone_infra'], '#041e2840', None,
             '10.11.1.x  INFRASTRUCTURE  \u2502  Servers & containers  \u2502  Always on  \u2502  No filter',
             fontsize=9, radius=0.004, lw=1.5)

    # Filtered zones
    fz_y = tier_y - 0.028
    fzones = [
        ('.9.x  DVGS',  'Girls School  \u2502  filter:75 MITM  \u2502  7-22 daily',     C['zone_dvgs'], 0.03,  0.22),
        ('.10.x DVBS',  'Boys School  \u2502  filter:75 MITM  \u2502  Time-windowed',   C['zone_dvbs'], 0.26,  0.22),
        ('.8.x  ADMIN', 'Restricted  \u2502  filter:50  \u2502  Always on',              C['zone_admin'], 0.49,  0.22),
        ('.15.x DRBU',  'University  \u2502  filter:400  \u2502  Always on',             C['zone_drbu'], 0.72,  0.25),
    ]
    for label, desc, color, zx, zw in fzones:
        glow_box(ax, zx, fz_y, zw, 0.022,
                 color, C['bg2'], None,
                 label, desc, fontsize=8, radius=0.004, lw=1.5)

    # Device zones
    dz_y = fz_y - 0.026
    dzones = [
        ('.12.x  SWITCHES',  '80+ managed HP/Cisco',  C['switch']),
        ('.14.x  PHONES',    'Student phones  f:400',  C['text_dim']),
        ('.19.x  LAPTOPS',   'Student  f:75',          C['text_dim']),
        ('.21-25 STAFF',     'Faculty/home  f:400',    C['text']),
    ]
    dw = 0.22
    dgap = (0.94 - 4 * dw) / 3
    dx = 0.03
    for label, desc, color in dzones:
        glow_box(ax, dx, dz_y, dw, 0.020,
                 color, C['bg2'], None,
                 f'{label}  \u2502  {desc}',
                 fontsize=7, radius=0.004, lw=1)
        dx += dw + dgap

    # Trust level labels
    for txt, ty, tc in [('TRUSTED', tier_y+0.011, C['zone_infra']),
                        ('FILTERED', fz_y+0.011, C['zone_dvgs']),
                        ('DEVICES', dz_y+0.010, C['text_dim'])]:
        ax.text(0.015, ty, txt, fontsize=7 * FS, fontweight='bold', color=tc,
                rotation=90, va='center', ha='center', zorder=10)

    # ════════════════════════════════════════════════════════════
    # CONTENT FILTERING
    # ════════════════════════════════════════════════════════════
    section_label(ax, 0.03, 0.285, 'CONTENT FILTERING  (E2Guardian on srv-gw)', C['gw'])

    cf_y = 0.257
    filter_groups = [
        ('Adult',           'default',    '400', '300',  'Staff, DRBU, faculty',       C['text']),
        ('Adult No Bypass', '',           '175', '0',    '15 specific staff IPs',       C['zone_admin']),
        ('Restricted',      '10.11.8.x',  '50',  '0',   'Admin subnet',               C['gw']),
        ('IGDVS',           '10.11.9-10.x','75', 'MITM','Schools + SSL interception',  C['zone_dvgs']),
    ]
    hdrs = [('GROUP', 0.04), ('SUBNET', 0.20), ('LIMIT', 0.33), ('BYPASS', 0.40), ('APPLIES TO', 0.49)]
    for htext, hx in hdrs:
        ax.text(hx, cf_y + 0.018, htext, fontsize=8 * FS, fontweight='bold',
                color=C['text_dim'], zorder=10, fontfamily='monospace')
    ax.plot([0.03, 0.70], [cf_y + 0.015, cf_y + 0.015], color=C['grid_accent'], lw=0.7, zorder=10)

    for i, (name, subnet, limit, bypass, applies, color) in enumerate(filter_groups):
        fy = cf_y + 0.003 - i * 0.012
        ax.text(0.04, fy, name, fontsize=8.5 * FS, fontweight='bold', color=color, zorder=10)
        ax.text(0.20, fy, subnet, fontsize=8 * FS, color=C['text_dim'], zorder=10, fontfamily='monospace')
        ax.text(0.33, fy, limit, fontsize=8.5 * FS, color=C['text'], zorder=10, fontfamily='monospace')
        ax.text(0.40, fy, bypass, fontsize=8.5 * FS, color=C['text'], zorder=10, fontfamily='monospace')
        ax.text(0.49, fy, applies, fontsize=8 * FS, color=C['text_dim'], zorder=10)

    # Timed internet schedules (right side)
    ax.text(0.72, cf_y + 0.018, 'TIMED INTERNET SCHEDULES', fontsize=8 * FS,
            fontweight='bold', color=C['gw'], zorder=10, fontfamily='monospace')
    ax.plot([0.72, 0.97], [cf_y + 0.015, cf_y + 0.015], color=C['grid_accent'], lw=0.7, zorder=10)
    schedules = [
        ('DVBS School',   '6-10:30, 11:30-16:30  M-F'),
        ('DVBS Comm Ctr', '12-14:30, 16-17, 18-22  M-F'),
        ('DVGS',          '7:00-22:00  daily'),
        ('DVGS CS Lab',   '8-10:30, 12-18:30  M-F'),
    ]
    for i, (zone, sched) in enumerate(schedules):
        sy = cf_y + 0.003 - i * 0.012
        ax.text(0.72, sy, zone, fontsize=8.5 * FS, fontweight='bold', color=C['text'], zorder=10)
        ax.text(0.85, sy, sched, fontsize=8 * FS, color=C['text_dim'], zorder=10, fontfamily='monospace')

    # ════════════════════════════════════════════════════════════
    # CAMPUS SWITCH FABRIC
    # ════════════════════════════════════════════════════════════
    section_label(ax, 0.03, 0.205, 'LAYER 6 \u2502 CAMPUS SWITCH FABRIC  (10.11.12.x  \u2502  80+ managed switches)', C['switch'])

    # Aggregation
    agg_y = 0.182
    glow_box(ax, 0.30, agg_y, 0.40, 0.018,
             C['switch'], C['sw_fill'], None,
             'sw-mpoe .12.30  \u2192  sw-ao-srvrm .12.31',
             'WAN & server room uplinks',
             fontsize=8.5, radius=0.005, lw=2)

    # Building clusters
    bld_y = 0.125
    bld_h = 0.046
    buildings = [
        ('DVGS',  'Girls School', ['CS Lab .12.44', 'Dorm .12.148', 'Library .12.97',
                                    'ES Admin .12.206', 'Furnace .12.32'],
         C['zone_dvgs'], 0.03, 0.125),
        ('DVBS',  'Boys School', ['CS Lab .12.179', 'Main Ofc .12.209', 'Comm Ctr .12.158',
                                   'Juan Ofc .12.37', 'Basement .12.43'],
         C['zone_dvbs'], 0.165, 0.125),
        ('1234',  'Admin Bldg', ['Machine Rm .12.172', 'Net Room .12.38',
                                  'Spike Cube .12.216'],
         C['zone_admin'], 0.30, 0.125),
        ('AO',    'Admin Office', ['Server Rm .12.31', 'Attic .12.167',
                                    'Front Desk .12.156'],
         C['text'], 0.435, 0.125),
        ('ToB',   'Tower of Bliss', ['Center .12.34', 'Elevator .12.165',
                                      'Financial .12.241', 'EnvSci .12.205'],
         C['deploy'], 0.57, 0.125),
        ('DRBU',  'University', ['CS Lab .12.242', 'Lib Up .12.93', 'Lib Dn .12.141',
                                  'Cdorm .12.169', 'ER main .12.39'],
         C['zone_drbu'], 0.705, 0.135),
        ('OTHER', 'Campus-wide', ['JGH .12.131', 'Laundry .12.211',
                                   'Restaurant .12.91', 'Solar .12.199'],
         C['monitor'], 0.85, 0.125),
    ]

    for bname, bdesc, bswitches, bcolor, bx, bw in buildings:
        glow_box(ax, bx, bld_y, bw, bld_h,
                 bcolor, C['bg2'], None, radius=0.004, lw=1.5)
        ax.text(bx + bw/2, bld_y + bld_h - 0.005, bname,
                ha='center', fontsize=10 * FS, fontweight='bold', color=bcolor, zorder=10)
        ax.text(bx + bw/2, bld_y + bld_h - 0.015, bdesc,
                ha='center', fontsize=7 * FS, color=C['text_dim'], zorder=10)
        sw_text = '\n'.join(bswitches[:4])
        if len(bswitches) > 4:
            sw_text += f'\n+{len(bswitches)-4} more'
        ax.text(bx + bw/2, bld_y + 0.005, sw_text,
                ha='center', va='bottom', fontsize=5.5 * FS, color=C['text_dim'],
                zorder=10, fontfamily='monospace', linespacing=1.2)
        pipe(ax, bx + bw/2, bld_y + bld_h, 0.50, agg_y, bcolor, lw=1.5)

    # ════════════════════════════════════════════════════════════
    # DNS ZONE TABLE
    # ════════════════════════════════════════════════════════════
    section_label(ax, 0.03, 0.115, 'DNS ZONE RECORDS  (.cttb domain)', C['dns'])

    dns_records = [
        ('gw',         '10.11.1.1',   'Gateway/FW/NTP'),
        ('srv-vm',     '10.11.1.3',   'VM host'),
        ('srv-nas',    '10.11.1.5',   'NAS'),
        ('fileserver', '10.11.1.18',  'NFS home dirs'),
        ('dnsmasq',    '10.11.1.19',  'DNS cache'),
        ('log-srv',    '10.11.1.20',  'Syslog'),
        ('git',        '10.11.1.21',  'Git server'),
        ('apt',        '10.11.1.22',  'Apt mirror'),
        ('pxe',        '10.11.1.23',  'PXE / TFTP'),
        ('ldap',       '10.11.1.25',  'OpenLDAP'),
    ]
    dns_records2 = [
        ('mon',           '10.11.1.26',  'Monitoring'),
        ('library.igdvs', '10.11.1.27',  'Koha library'),
        ('ub-igdvs',      '10.11.1.28',  'Unbound (schools)'),
        ('ub-adult',      '10.11.1.29',  'Unbound (adult)'),
        ('wiki',          '10.11.1.31',  'Wiki'),
        ('asterisk',      '10.11.1.32',  'VoIP PBX'),
        ('cups-cttb',     '10.11.1.36',  'Print server'),
        ('lxc-sltp',      '10.11.1.39',  'Sanskrit'),
        ('sis.drbu',      '10.11.1.41',  'Student info'),
        ('time',          '10.11.1.1',   'NTP (alias)'),
    ]

    dns_y = 0.103
    row_h = 0.009
    for hx, ht in [(0.04, 'RECORD'), (0.16, 'IP'), (0.26, 'SERVICE')]:
        ax.text(hx, dns_y, ht, fontsize=7.5 * FS, fontweight='bold',
                color=C['text_dim'], zorder=10, fontfamily='monospace')
    for hx, ht in [(0.38, 'RECORD'), (0.52, 'IP'), (0.63, 'SERVICE')]:
        ax.text(hx, dns_y, ht, fontsize=7.5 * FS, fontweight='bold',
                color=C['text_dim'], zorder=10, fontfamily='monospace')
    ax.plot([0.03, 0.35], [dns_y - 0.003, dns_y - 0.003], color=C['grid_accent'], lw=0.6, zorder=10)
    ax.plot([0.37, 0.72], [dns_y - 0.003, dns_y - 0.003], color=C['grid_accent'], lw=0.6, zorder=10)

    for i, (rec, ip, svc) in enumerate(dns_records):
        ry = dns_y - 0.010 - i * row_h
        ax.text(0.04, ry, f'{rec}.cttb', fontsize=7.5 * FS, color=C['dns'],
                zorder=10, fontfamily='monospace')
        ax.text(0.16, ry, ip, fontsize=7.5 * FS, color=C['text_dim'],
                zorder=10, fontfamily='monospace')
        ax.text(0.26, ry, svc, fontsize=7.5 * FS, color=C['text'], zorder=10)

    for i, (rec, ip, svc) in enumerate(dns_records2):
        ry = dns_y - 0.010 - i * row_h
        ax.text(0.38, ry, f'{rec}.cttb', fontsize=7.5 * FS, color=C['dns'],
                zorder=10, fontfamily='monospace')
        ax.text(0.52, ry, ip, fontsize=7.5 * FS, color=C['text_dim'],
                zorder=10, fontfamily='monospace')
        ax.text(0.63, ry, svc, fontsize=7.5 * FS, color=C['text'], zorder=10)

    # ════════════════════════════════════════════════════════════
    # QUICK REFERENCE
    # ════════════════════════════════════════════════════════════
    section_label(ax, 0.74, 0.115, 'WHAT RUNS WHERE?', C['white'])

    qr = [
        ('Debug internet/firewall',  'srv-gw',           '10.11.1.1',   C['gw']),
        ('Manage LXD containers',    'srv-vm/srv-nas',    '.1.3/.1.5',   C['vm']),
        ('Manage LDAP accounts',      'lxc-ldap',         '.1.25',       C['auth']),
        ('Fix DNS',                   'lxc-ub-adult/igdvs','.1.29/.28',  C['dns']),
        ('Fix printing',              'lxc-cups-*',       '.1.36-38',    C['print']),
        ('PXE boot machine',          'lxc-pxe',          '.1.23',       C['deploy']),
        ('NFS home dirs',             'lxc-fs',           '.1.18',       C['storage']),
        ('Centralized logs',          'lxc-log',          '.1.20',       C['log']),
        ('Update apt mirrors',        'lxc-debmirror',    '.1.22',       C['deploy']),
        ('VoIP / phones',             'lxc-asterisk',     '.1.32',       C['voip']),
        ('Library (Koha)',            'lxc-koha',         '.1.27',       C['library']),
        ('Monitoring',                'lxc-mon/metrics',  '.1.26/.24',   C['monitor']),
        ('Git repos',                 'lxc-git',          '.1.21',       C['app']),
        ('SSH from outside',          'lxc-jumpbox',      '.1.33',       C['gw']),
    ]

    qr_y = 0.103
    for hx, ht in [(0.74, 'NEED TO\u2026'), (0.88, 'GO TO'), (0.96, 'IP')]:
        ax.text(hx, qr_y, ht, fontsize=7.5 * FS, fontweight='bold',
                color=C['text_dim'], zorder=10, fontfamily='monospace')
    ax.plot([0.74, 0.97], [qr_y - 0.003, qr_y - 0.003], color=C['grid_accent'], lw=0.6, zorder=10)

    for i, (task, target, ip, color) in enumerate(qr):
        qy = qr_y - 0.010 - i * row_h
        ax.text(0.74, qy, task, fontsize=7.5 * FS, color=C['text'], zorder=10)
        ax.text(0.88, qy, target, fontsize=7.5 * FS, fontweight='bold',
                color=color, zorder=10, fontfamily='monospace')
        ax.text(0.96, qy, ip, fontsize=7 * FS, color=C['text_dim'],
                zorder=10, fontfamily='monospace')

    # ════════════════════════════════════════════════════════════
    # FOOTER: ACCESS & CREDENTIALS
    # ════════════════════════════════════════════════════════════
    footer_y = 0.006
    glow_box(ax, 0.03, footer_y, 0.94, 0.018,
             C['auth'], C['auth_fill'], None, radius=0.005, lw=1.5)

    ax.text(0.05, footer_y + 0.012, 'ACCESS:',
            fontsize=10 * FS, fontweight='bold', color=C['auth'], zorder=10,
            fontfamily='monospace', va='center')
    ax.text(0.12, footer_y + 0.012,
            'Jumpbox: ssh administrator@cttb (password)  \u2502  '
            'Infrastructure: pubkey only  \u2502  '
            'Containers: lxc exec <name> bash  \u2502  '
            'Password hosts: administrator / 4m1t0f0 (sudo)',
            fontsize=8 * FS, color=C['text'], zorder=10, va='center')

    return fig


if __name__ == '__main__':
    outdir = os.path.dirname(os.path.abspath(__file__))
    outpath = os.path.join(outdir, 'cttb-infrastructure.pdf')

    fig = draw_poster()
    fig.savefig(outpath, facecolor=fig.get_facecolor(), dpi=150,
                bbox_inches='tight', pad_inches=0.3)
    plt.close(fig)
    print(f'PDF saved to: {outpath}')
    print(f'Size: {os.path.getsize(outpath) / 1024:.0f} KB')
