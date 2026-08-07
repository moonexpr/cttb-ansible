#!/usr/bin/env python3
"""create-sudhanix-s0-installer.py — build a stage-0 autoinstall USB installer.

Stage 0 is the bootable stick that turns a bare machine into a stage-1 host:
minimal Ubuntu 24.04 Server with openssh-server, python3, and the operator's
keys, ready for an Ansible stage-2 run.

Unlike the PXE path (plays/sudhanix26-rollout-stage0-bios.yml), the autoinstall
seed rides on the stick at /cdrom/nocloud/, so nothing on the CTTB network needs
to be reachable at install time. Defaults therefore point at the public Ubuntu
archive rather than apt.cttb — this tool exists for hosts that live outside the
campus perimeter.

Destructive writes are dry-run until --risks-confirmed, matching utils/ldap.

Usage:
    utils/create-sudhanix-s0-installer.py --hostname foo --disk /dev/disk8
    utils/create-sudhanix-s0-installer.py --hostname foo --disk /dev/disk8 --risks-confirmed
"""
import argparse
import hashlib
import os
import re
import shutil
import struct
import subprocess
import sys
import urllib.request
from dataclasses import dataclass, field
from pathlib import Path

import yaml

REPO_ROOT = Path(__file__).resolve().parent.parent
ROLE_DEFAULTS = REPO_ROOT / "roles" / "netinstall-2404" / "defaults" / "main.yml"
BUILD_DIR = REPO_ROOT / "build" / "autoinstall-usb"

DEFAULT_ISO_URL = (
    "https://releases.ubuntu.com/24.04/ubuntu-24.04.4-live-server-amd64.iso"
)
DEFAULT_APT_MIRROR = "http://archive.ubuntu.com/ubuntu/"
DEFAULT_APT_SECURITY = "http://security.ubuntu.com/ubuntu/"

# EFI System Partition type GUID C12A7328-F81F-11D2-BA4B-00A0C93EC93B in the
# on-disk mixed-endian byte order, which is also the form -append_partition wants.
ESP_TYPE_GUID = bytes.fromhex("28732ac11ff8d211ba4b00a0c93ec93b")

LABEL_RE = re.compile(r"^[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?$", re.I)

# Minimum for an Ansible stage-2 run to reach the host and do anything.
BASE_PACKAGES = ("openssh-server", "python3")

# subiquity validates `timezone` against `timedatectl list-timezones`, which lists
# canonical zones only. tzdata's backward-compat aliases (US/Pacific and friends)
# are NOT in it and are not even shipped in the installer image, so passing one
# crashes the installer with ValueError several minutes into an unattended run.
CANONICAL_TZ_AREAS = frozenset({
    "Africa", "America", "Antarctica", "Arctic", "Asia", "Atlantic",
    "Australia", "Etc", "Europe", "Indian", "Pacific",
})
LEGACY_TZ_ALIASES = {
    "US/Pacific": "America/Los_Angeles",
    "US/Mountain": "America/Denver",
    "US/Central": "America/Chicago",
    "US/Eastern": "America/New_York",
    "US/Alaska": "America/Anchorage",
    "US/Hawaii": "Pacific/Honolulu",
    "US/Arizona": "America/Phoenix",
}


def die(msg: str) -> None:
    print(f"ERROR: {msg}", file=sys.stderr)
    sys.exit(1)


def run(cmd: list, **kw) -> subprocess.CompletedProcess:
    return subprocess.run(cmd, check=True, **kw)


# ── configuration ─────────────────────────────────────────────────────────────


@dataclass(frozen=True)
class Config:
    """Fully validated build inputs. Constructed once; the rest of the tool trusts it."""

    hostname: str
    disk: str
    username: str
    fullname: str
    password_hash: str
    authorized_keys: tuple
    packages: tuple
    locale: str
    keyboard: str
    timezone: str
    banner: str
    apt_mirror: str
    apt_security: str
    iso_url: str
    iso_path: Path
    output_iso: Path
    confirmed: bool
    keep_work: bool

    @property
    def work_dir(self) -> Path:
        return BUILD_DIR / f"work-{self.hostname}"

    @property
    def raw_disk(self) -> str:
        """macOS raw device — an order of magnitude faster to dd than the buffered node."""
        return self.disk.replace("/dev/disk", "/dev/rdisk")


def canonical_timezone(tz: str) -> str:
    """Reject or rewrite a timezone subiquity would refuse, at build time.

    Catching this here turns a crash four minutes into an unattended install on
    a machine you may not be standing next to into an error before the ISO is
    even downloaded.
    """
    if tz in ("", "geoip", "UTC"):
        return tz
    if tz in LEGACY_TZ_ALIASES:
        canon = LEGACY_TZ_ALIASES[tz]
        print(f"NOTE: {tz!r} is a tzdata backward-compat alias and is not in "
              f"`timedatectl list-timezones`; subiquity rejects it. Using {canon!r}.")
        return canon
    area, _, rest = tz.partition("/")
    if not rest or area not in sorted(CANONICAL_TZ_AREAS):
        die(f"{tz!r} is not a canonical IANA timezone. subiquity validates against "
            f"`timedatectl list-timezones` and will crash on anything else. "
            f"Use an Area/Location name such as America/Los_Angeles.")
    return tz


def role_defaults() -> dict:
    if not ROLE_DEFAULTS.is_file():
        die(f"role defaults not found at {ROLE_DEFAULTS}")
    return yaml.safe_load(ROLE_DEFAULTS.read_text()) or {}


def build_config(args) -> Config:
    d = role_defaults()

    hostname = args.hostname.strip().rstrip(".")
    if not all(LABEL_RE.match(label) for label in hostname.split(".")):
        die(f"{hostname!r} is not a valid hostname")
    if hostname.endswith(".local"):
        print("NOTE: .local is supplied by mDNS, not stored in /etc/hostname. "
              "Consider the short name plus --package avahi-daemon.")

    keys = tuple(args.authorized_key) if args.authorized_key else tuple(
        k for k in (d.get("ni_ansible_ssh_pubkey"), d.get("ni_jc_ssh_pubkey")) if k
    )
    if not keys:
        die("no authorized SSH keys resolved; pass --authorized-key")

    password_hash = args.password_hash or d.get("ni_admin_password_crypted") or ""
    if not password_hash:
        die("no password hash resolved; pass --password-hash")

    iso_url = args.iso_url or DEFAULT_ISO_URL
    iso_path = (
        Path(args.iso).expanduser().resolve()
        if args.iso
        else BUILD_DIR / iso_url.rsplit("/", 1)[-1]
    )
    output_iso = (
        Path(args.output_iso).expanduser().resolve()
        if args.output_iso
        else BUILD_DIR / f"sudhanix-s0-{hostname}.iso"
    )

    return Config(
        hostname=hostname,
        disk=resolve_disk(args.disk, force=args.force_nonremovable),
        username=args.username or d.get("ni_admin_user", "administrator"),
        fullname=args.fullname or d.get("ni_admin_fullname", "Administrator"),
        password_hash=password_hash,
        authorized_keys=keys,
        packages=tuple(dict.fromkeys(BASE_PACKAGES + tuple(args.package or ()))),
        locale=args.locale or d.get("ni_locale", "en_US.UTF-8"),
        keyboard=args.keyboard or d.get("ni_keyboard_layout", "us"),
        timezone=canonical_timezone(
            args.timezone or d.get("ni_timezone") or "America/Los_Angeles"),
        banner="" if args.no_banner else d.get("ni_stage1_description", "Sudhanix 26"),
        apt_mirror=args.apt_mirror or DEFAULT_APT_MIRROR,
        apt_security=args.apt_security or DEFAULT_APT_SECURITY,
        iso_url=iso_url,
        iso_path=iso_path,
        output_iso=output_iso,
        confirmed=args.risks_confirmed,
        keep_work=args.keep_work,
    )


# ── target disk ───────────────────────────────────────────────────────────────


def diskutil_info(dev: str) -> dict:
    out = subprocess.run(
        ["diskutil", "info", dev], capture_output=True, text=True
    ).stdout
    info = {}
    for line in out.splitlines():
        if ":" in line:
            k, _, v = line.partition(":")
            info[k.strip()] = v.strip()
    return info


def resolve_disk(target: str, *, force: bool) -> str:
    if target.startswith("/Volumes/"):
        node = diskutil_info(target).get("Device Node", "")
        if not node:
            die(f"could not resolve {target} to a device node")
        # A mount point resolves to a slice (disk8s1); we need the whole disk.
        target = re.sub(r"s\d+$", "", node)
        print(f"Resolved mount point to whole disk: {target}")

    if not re.fullmatch(r"/dev/disk\d+", target):
        die(f"{target!r} is not a whole-disk device node (expected /dev/diskN)")

    info = diskutil_info(target)
    if not info:
        die(f"{target} is not a disk this system knows about")

    internal = info.get("Device Location", "").lower() == "internal"
    removable = "removable" in info.get("Removable Media", "").lower()
    if internal or not removable:
        detail = (
            f"  Device Location : {info.get('Device Location', '?')}\n"
            f"  Removable Media : {info.get('Removable Media', '?')}\n"
            f"  Protocol        : {info.get('Protocol', '?')}\n"
            f"  Volume Name     : {info.get('Volume Name', '?')}"
        )
        if not force:
            die(
                f"{target} does not look like removable external media:\n{detail}\n"
                "Refusing. Pass --force-nonremovable if this really is the target."
            )
        print(f"WARNING: proceeding with non-removable target {target}:\n{detail}")

    return target


# ── ISO acquisition and inspection ────────────────────────────────────────────


def iso_volume_id(iso: Path) -> str:
    """Volume identifier from the ISO9660 Primary Volume Descriptor (LBA 16)."""
    with iso.open("rb") as fh:
        fh.seek(16 * 2048)
        pvd = fh.read(2048)
    if pvd[1:6] != b"CD001":
        die(f"{iso} is not an ISO9660 image (no CD001 magic at LBA 16)")
    return pvd[40:72].decode("ascii", "replace").rstrip()


def esp_extent(iso: Path) -> tuple:
    """(first_lba, last_lba) of the EFI System Partition, read from the ISO's GPT.

    build-usb.sh hardcoded these for the 24.04.2 image. Against any other ISO the
    hardcoded values produce a stick that boots on BIOS and fails on UEFI, so they
    are derived here instead.
    """
    with iso.open("rb") as fh:
        fh.seek(512)
        header = fh.read(512)
        if header[:8] != b"EFI PART":
            die(f"{iso} has no GPT header at LBA 1; not a hybrid ISO")
        entry_lba, num_entries, entry_size = struct.unpack_from("<Q", header, 72)[0], \
            struct.unpack_from("<I", header, 80)[0], struct.unpack_from("<I", header, 84)[0]

        fh.seek(entry_lba * 512)
        table = fh.read(num_entries * entry_size)

    found = []
    for i in range(num_entries):
        entry = table[i * entry_size:(i + 1) * entry_size]
        if entry[:16] == ESP_TYPE_GUID:
            first, last = struct.unpack_from("<QQ", entry, 32)
            found.append((first, last))

    if len(found) != 1:
        die(f"expected exactly one EFI System Partition in {iso}, found {len(found)}")

    first, last = found[0]
    size_mb = (last - first + 1) * 512 / 1024 / 1024
    if not (first > 0 and 1 <= size_mb <= 16):
        die(f"implausible ESP extent {first}-{last} ({size_mb:.1f} MB)")
    return first, last


def acquire_iso(cfg: Config) -> None:
    if cfg.iso_path.is_file() and cfg.iso_path.stat().st_size > 0:
        size_gb = cfg.iso_path.stat().st_size / 1e9
        print(f"Using cached ISO: {cfg.iso_path} ({size_gb:.2f} GB)")
        return

    BUILD_DIR.mkdir(parents=True, exist_ok=True)
    print(f"Downloading {cfg.iso_url}\n           -> {cfg.iso_path}")
    tmp = cfg.iso_path.with_suffix(".part")

    def progress(blocks, block_size, total):
        if total > 0:
            pct = min(100, blocks * block_size * 100 // total)
            print(f"\r  {pct}%", end="", flush=True)

    urllib.request.urlretrieve(cfg.iso_url, tmp, reporthook=progress)
    print()
    tmp.rename(cfg.iso_path)


# ── autoinstall seed ──────────────────────────────────────────────────────────


def render_seed(cfg: Config) -> str:
    keys = "\n".join(f'      - "{k}"' for k in cfg.authorized_keys)
    pkgs = "\n".join(f"    - {p}" for p in cfg.packages)
    seed = f"""#cloud-config
# Stage-0 autoinstall seed for {cfg.hostname}.
# Generated by utils/create-sudhanix-s0-installer.py -- do not hand-edit the copy
# on the stick; rebuild instead.
#
# This host lives OUTSIDE the CTTB network: the apt mirror is the public Ubuntu
# archive, not apt.cttb, and the seed is read from /cdrom/nocloud/ rather than
# fetched from pxe.cttb.
autoinstall:
  version: 1
  locale: {cfg.locale}
  keyboard:
    layout: {cfg.keyboard}
  network:
    version: 2
    ethernets:
      id0:
        match:
          name: "en*"
        dhcp4: true
        dhcp6: false
  apt:
    preserve_sources_list: false
    mirror-selection:
      primary:
        - uri: {cfg.apt_mirror}
      security:
        - uri: {cfg.apt_security}
    geoip: false
  storage:
    layout:
      name: direct
  identity:
    hostname: {cfg.hostname}
    realname: {cfg.fullname}
    username: {cfg.username}
    password: "{cfg.password_hash}"
  ssh:
    install-server: true
    allow-pw: true
    authorized-keys:
{keys}
  timezone: {cfg.timezone}
  updates: security
  # Ansible owns the full desktop stack; this install is Ansible bootstrap only.
  packages:
{pkgs}
"""
    if cfg.banner:
        # late-commands may touch /etc only: cloud-init creates the user on first
        # boot, so usermod/authorized_keys writes here fail with exit 6.
        seed += f"""  late-commands:
    # Stage-1 console banner, replaced by roles/common in stage 2. agetty prints
    # the hostname before the hardcoded word "login:", so LOGIN_PLAIN_PROMPT drops
    # it and the issue file ends with "technician " and no newline, yielding
    # "technician login:". The trailing space is load-bearing.
    # Escapes: \\S = os-release PRETTY_NAME, \\4 = first IPv4, \\l = tty.
    - |
      cat <<'ISSUEEOF' > /target/etc/issue
      {cfg.banner} running on \\S in teletype mode.
      This computer is ready for the Stage 2 installation.
      IP: \\4  (\\l)

      ISSUEEOF
      printf '%s' 'technician ' >> /target/etc/issue
    # login.defs is last-line-wins, so appending beats any stock value.
    - echo 'LOGIN_PLAIN_PROMPT yes' >> /target/etc/login.defs
"""
    return seed


def validate_seed(seed: str, cfg: Config) -> None:
    """Fail the build, not the install, if the seed is malformed or campus-bound."""
    parsed = yaml.safe_load(seed)
    ai = parsed.get("autoinstall", {})
    if ai.get("version") != 1:
        die("rendered seed has no autoinstall.version == 1")
    if ai.get("identity", {}).get("hostname") != cfg.hostname:
        die("rendered seed hostname does not match the requested hostname")

    apt = ai.get("apt", {}).get("mirror-selection", {})
    uris = [e["uri"] for group in apt.values() for e in group]
    campus = [u for u in uris if "cttb" in u]
    if campus:
        die(f"seed points at campus-only apt mirrors, unreachable off-network: {campus}")


# ── remaster ──────────────────────────────────────────────────────────────────


GRUB_PARAMS = "autoinstall ds=nocloud\\;s=/cdrom/nocloud/"


def patch_grub(grub_cfg: Path, cfg: Config) -> int:
    """Add autoinstall params to every casper boot line. Returns lines patched."""
    text = grub_cfg.read_text()
    patched = 0

    def add_params(m):
        nonlocal patched
        line = m.group(0)
        if "autoinstall" in line:
            return line
        patched += 1
        # The stock line ends in ' ---'; params belong before that separator.
        if line.rstrip().endswith("---"):
            head, _, _ = line.rstrip().rpartition("---")
            return f"{head.rstrip()} {GRUB_PARAMS} ---"
        return f"{line.rstrip()} {GRUB_PARAMS}"

    text = re.sub(r"^\s*linux\s+/casper/vmlinuz.*$", add_params, text, flags=re.M)
    text = text.replace(
        "Try or Install Ubuntu Server",
        f"Autoinstall Sudhanix stage 0 ({cfg.hostname})",
    )
    text = re.sub(r"^set timeout=\d+", "set timeout=5", text, flags=re.M)
    grub_cfg.write_text(text)
    return patched


def remaster(cfg: Config, seed: str) -> None:
    work = cfg.work_dir
    iso_tree = work / "iso"
    if work.exists():
        shutil.rmtree(work)
    (work / "nocloud").mkdir(parents=True)

    print(f"Extracting ISO -> {iso_tree}")
    run(["xorriso", "-osirrox", "on", "-indev", str(cfg.iso_path),
         "-extract", "/", str(iso_tree)],
        stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)

    # xorriso extracts read-only; the grub.cfg edit and the nocloud copy need write.
    for root, dirs, files in os.walk(iso_tree):
        for name in dirs + files:
            p = Path(root) / name
            p.chmod(p.stat().st_mode | 0o200)

    (work / "nocloud" / "user-data").write_text(seed)
    (work / "nocloud" / "meta-data").write_text("")
    shutil.copytree(work / "nocloud", iso_tree / "nocloud")
    # Keep an auditable copy of exactly what shipped, next to the output ISO.
    (cfg.output_iso.with_suffix(".user-data")).write_text(seed)

    grub_cfg = iso_tree / "boot" / "grub" / "grub.cfg"
    if not grub_cfg.is_file():
        die(f"no grub.cfg in the extracted ISO at {grub_cfg}")
    n = patch_grub(grub_cfg, cfg)
    if n == 0:
        die("patched no casper boot lines in grub.cfg; the ISO layout has changed")
    print(f"Patched {n} boot line(s) in boot/grub/grub.cfg")

    first, last = esp_extent(cfg.iso_path)
    volid = iso_volume_id(cfg.iso_path)
    print(f"ESP extent {first}-{last} ({(last - first + 1) * 512 / 1e6:.1f} MB); "
          f"volume id {volid!r}")

    print(f"Repacking -> {cfg.output_iso}")
    run([
        "xorriso", "-as", "mkisofs",
        "-r", "-V", volid,
        "-o", str(cfg.output_iso),
        "--grub2-mbr",
        f"--interval:local_fs:0s-15s:zero_mbrpt,zero_gpt:{cfg.iso_path}",
        "--protective-msdos-label",
        "-partition_cyl_align", "off", "-partition_offset", "16",
        "--mbr-force-bootable",
        "-append_partition", "2", ESP_TYPE_GUID.hex(),
        f"--interval:local_fs:{first}d-{last}d::{cfg.iso_path}",
        "-appended_part_as_gpt",
        "-iso_mbr_part_type", "a2a0d0ebe5b9334487c068b6b72699c7",
        "-c", "/boot.catalog",
        "-b", "/boot/grub/i386-pc/eltorito.img",
        "-no-emul-boot", "-boot-load-size", "4", "-boot-info-table",
        "--grub2-boot-info",
        "-eltorito-alt-boot",
        "-e", "--interval:appended_partition_2:::",
        "-no-emul-boot",
        str(iso_tree),
    ], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)

    if not cfg.keep_work:
        shutil.rmtree(work)


# ── write and verify ──────────────────────────────────────────────────────────


VERIFY_BYTES = 64 * 1024 * 1024
MIB = 1024 * 1024
# Byte counts, not "4m": sudo may resolve dd to GNU coreutils, which rejects the
# BSD lowercase suffix ("dd: invalid number: '4m'"). A bare number suits both.
DD_BLOCK_SIZE = 4 * MIB


def sha256_head(path: str, nbytes: int, *, sudo: bool = False) -> str:
    if sudo:
        out = subprocess.run(
            ["sudo", "dd", f"if={path}", f"bs={MIB}", f"count={nbytes // MIB}"],
            capture_output=True, check=True,
        ).stdout
    else:
        with open(path, "rb") as fh:
            out = fh.read(nbytes)
    return hashlib.sha256(out).hexdigest()


def write_usb(cfg: Config) -> None:
    print(f"\nUnmounting {cfg.disk}")
    subprocess.run(["diskutil", "unmountDisk", cfg.disk], check=False,
                   stdout=subprocess.DEVNULL)

    print(f"Writing {cfg.output_iso.name} -> {cfg.raw_disk} (sudo required)")
    run(["sudo", "dd", f"if={cfg.output_iso}", f"of={cfg.raw_disk}",
         f"bs={DD_BLOCK_SIZE}"])
    run(["sync"])

    print("Verifying written image...")
    expect = sha256_head(str(cfg.output_iso), VERIFY_BYTES)
    actual = sha256_head(cfg.raw_disk, VERIFY_BYTES, sudo=True)
    if expect != actual:
        die(f"readback mismatch over first {VERIFY_BYTES // 1024 // 1024} MB:\n"
            f"  iso  {expect}\n  disk {actual}")
    print(f"Readback OK ({VERIFY_BYTES // 1024 // 1024} MB, sha256 {expect[:16]}...)")


# ── plan ──────────────────────────────────────────────────────────────────────


def existing_volumes(dev: str) -> list:
    """Volume names of the slices on a whole disk — what the operator is about to erase."""
    out = subprocess.run(["diskutil", "list", dev], capture_output=True, text=True).stdout
    names = []
    for slice_dev in re.findall(r"^\s*\d+:.*?(\bdisk\d+s\d+)\s*$", out, re.M):
        name = diskutil_info(f"/dev/{slice_dev}").get("Volume Name", "")
        if name and "Not applicable" not in name:
            names.append(f"{slice_dev}: {name}")
    return names


def print_plan(cfg: Config) -> None:
    info = diskutil_info(cfg.disk)
    print("\n=== BUILD PLAN ===")
    print(f"  hostname      : {cfg.hostname}")
    print(f"  user          : {cfg.username} ({cfg.fullname})")
    print(f"  ssh keys      : {len(cfg.authorized_keys)}")
    for k in cfg.authorized_keys:
        print(f"                  {k.split()[-1]}")
    print(f"  packages      : {', '.join(cfg.packages)}")
    print(f"  apt primary   : {cfg.apt_mirror}")
    print(f"  apt security  : {cfg.apt_security}")
    print(f"  locale/tz     : {cfg.locale} / {cfg.timezone}")
    print(f"  source ISO    : {cfg.iso_path}")
    print(f"  output ISO    : {cfg.output_iso}")
    print(f"  target disk   : {cfg.disk}  ({cfg.raw_disk} for the write)")
    print(f"                  {info.get('Device / Media Name', '?')}, "
          f"{info.get('Disk Size', '?').split(' (')[0]}, "
          f"{info.get('Protocol', '?')}, {info.get('Device Location', '?')}")
    for vol in existing_volumes(cfg.disk) or ["(no named volumes)"]:
        print(f"                  TO BE ERASED — {vol}")
    if not cfg.confirmed:
        print("\n  DRY RUN — nothing will be downloaded, built, or written.")
        print("  Re-run with --risks-confirmed to build the ISO and ERASE "
              f"{cfg.disk}.")
    else:
        print(f"\n  *** {cfg.disk} WILL BE ERASED ***")


# ── main ──────────────────────────────────────────────────────────────────────


def main() -> None:
    p = argparse.ArgumentParser(
        prog="create-sudhanix-s0-installer.py",
        description="Build a stage-0 Ubuntu 24.04 autoinstall USB for an "
                    "off-campus Sudhanix host.",
        formatter_class=argparse.RawDescriptionHelpFormatter,
    )
    p.add_argument("--hostname", required=True,
                   help="hostname baked into the autoinstall seed")
    p.add_argument("--disk", required=True, metavar="DEVICE",
                   help="/dev/diskN, or /Volumes/NAME to resolve via diskutil")
    p.add_argument("--risks-confirmed", action="store_true",
                   help="actually build and write (default is dry-run)")
    p.add_argument("--force-nonremovable", action="store_true",
                   help="allow a target that is not external removable media")

    src = p.add_argument_group("source")
    src.add_argument("--iso", metavar="PATH", help="use a local ISO instead of downloading")
    src.add_argument("--iso-url", metavar="URL", help=f"default {DEFAULT_ISO_URL}")

    seed = p.add_argument_group("seed")
    seed.add_argument("--apt-mirror", metavar="URI", help=f"default {DEFAULT_APT_MIRROR}")
    seed.add_argument("--apt-security", metavar="URI", help=f"default {DEFAULT_APT_SECURITY}")
    seed.add_argument("--username")
    seed.add_argument("--fullname")
    seed.add_argument("--password-hash", metavar="HASH")
    seed.add_argument("--authorized-key", action="append", metavar="KEY",
                      help="repeatable; replaces the default key set when given")
    seed.add_argument("--package", action="append", metavar="PKG",
                      help="repeatable; installed in addition to "
                           + " + ".join(BASE_PACKAGES))
    seed.add_argument("--locale")
    seed.add_argument("--keyboard")
    seed.add_argument("--timezone")
    seed.add_argument("--no-banner", action="store_true",
                      help="omit the stage-1 /etc/issue console banner")

    out = p.add_argument_group("output")
    out.add_argument("--output-iso", metavar="PATH")
    out.add_argument("--keep-work", action="store_true",
                     help="retain the extraction tree for inspection")

    args = p.parse_args()

    if not shutil.which("xorriso"):
        die("xorriso not found. Install it: brew install xorriso")

    cfg = build_config(args)
    seed_text = render_seed(cfg)
    validate_seed(seed_text, cfg)
    print_plan(cfg)

    if not cfg.confirmed:
        return

    BUILD_DIR.mkdir(parents=True, exist_ok=True)
    acquire_iso(cfg)
    remaster(cfg, seed_text)
    write_usb(cfg)

    print(f"\nDone. Stage-0 installer for {cfg.hostname} is on {cfg.disk}.")
    print(f"  Eject with: diskutil eject {cfg.disk}")
    print("  Boot the target host from USB (F12 for the boot menu on Dells).")
    print("  Secure Boot must be OFF; the install then runs unattended.")


if __name__ == "__main__":
    try:
        main()
    except subprocess.CalledProcessError as e:
        die(f"command failed ({e.returncode}): {' '.join(str(c) for c in e.cmd)}")
    except KeyboardInterrupt:
        sys.exit(130)
