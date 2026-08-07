#!/usr/bin/env python3
"""Acceptance checks for utils/create-sudhanix-s0-installer.py.

Every check here is non-destructive: nothing is written to a USB. The
post-write readback check (comparing the stick against the built ISO) lives in
the tool itself, because it can only run after a real write.

Usage:
    utils/tests/test-create-sudhanix-s0-installer.py [--iso PATH]
"""
import argparse
import importlib.util
import re
import sys
import yaml
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent.parent
TOOL = REPO_ROOT / "utils" / "create-sudhanix-s0-installer.py"

spec = importlib.util.spec_from_file_location("s0", TOOL)
s0 = importlib.util.module_from_spec(spec)
spec.loader.exec_module(s0)

FAILURES = []


def check(name, condition, detail=""):
    status = "PASS" if condition else "FAIL"
    print(f"  [{status}] {name}" + (f" — {detail}" if detail and not condition else ""))
    if not condition:
        FAILURES.append(name)


def fake_config(**over):
    d = s0.role_defaults()
    base = dict(
        hostname="testhost", disk="/dev/disk99",
        username=d["ni_admin_user"], fullname=d["ni_admin_fullname"],
        password_hash=d["ni_admin_password_crypted"],
        authorized_keys=(d["ni_ansible_ssh_pubkey"], d["ni_jc_ssh_pubkey"]),
        packages=s0.BASE_PACKAGES, assets_dir=None,
        locale=d["ni_locale"], keyboard=d["ni_keyboard_layout"],
        timezone=d["ni_timezone"], banner=d["ni_stage1_description"],
        apt_mirror=s0.DEFAULT_APT_MIRROR, apt_security=s0.DEFAULT_APT_SECURITY,
        iso_url=s0.DEFAULT_ISO_URL, iso_path=Path("/nonexistent.iso"),
        output_iso=Path("/tmp/unused.iso"), confirmed=False, keep_work=False,
    )
    base.update(over)
    return s0.Config(**base)


def test_seed():
    print("V3 — rendered seed")
    cfg = fake_config(hostname="offsite-01")
    seed = s0.render_seed(cfg)
    parsed = yaml.safe_load(seed)
    ai = parsed["autoinstall"]

    check("parses as YAML with autoinstall.version == 1", ai.get("version") == 1)
    check("hostname matches request",
          ai["identity"]["hostname"] == "offsite-01", ai["identity"]["hostname"])
    check("username/password carried from role defaults",
          ai["identity"]["username"] == "administrator"
          and ai["identity"]["password"].startswith("$1$"))
    check("both SSH keys authorized", len(ai["ssh"]["authorized-keys"]) == 2)
    check("openssh-server and python3 requested",
          set(ai["packages"]) == {"openssh-server", "python3"})

    extra = fake_config(packages=s0.BASE_PACKAGES + ("avahi-daemon",))
    check("--package appends without dropping the base set",
          yaml.safe_load(s0.render_seed(extra))["autoinstall"]["packages"]
          == ["openssh-server", "python3", "avahi-daemon"])

    uris = [e["uri"] for g in ai["apt"]["mirror-selection"].values() for e in g]
    check("apt points at the public archive",
          all("ubuntu.com" in u for u in uris), str(uris))
    # Comment prose and the ansible@cttb.us key comment may say "cttb"; what must
    # never appear is a *reachable* campus reference, which would hang the install.
    urls = re.findall(r"https?://[^\s\"']+", seed)
    check("no campus URL in the seed",
          not [u for u in urls if ".cttb" in u], str(urls))
    check("wired DHCP only, no wifi block", "wifis" not in ai["network"])

    # validate_seed must reject a campus-bound mirror rather than ship it.
    bad = fake_config(apt_mirror="http://apt.cttb/mirrors/ubuntu/")
    try:
        s0.validate_seed(s0.render_seed(bad), bad)
        check("validate_seed rejects a cttb mirror", False, "it accepted one")
    except SystemExit:
        check("validate_seed rejects a cttb mirror", True)

    nb = fake_config(banner="")
    check("--no-banner drops late-commands",
          "late-commands" not in yaml.safe_load(s0.render_seed(nb))["autoinstall"])


def test_gpt(iso: Path):
    print("V4 — GPT / ISO inspection")
    if not iso.is_file():
        check(f"ISO present at {iso}", False, "skipping GPT checks")
        return
    first, last = s0.esp_extent(iso)
    size_mb = (last - first + 1) * 512 / 1024 / 1024
    check("exactly one ESP found with a plausible extent",
          first > 0 and 1 <= size_mb <= 16, f"{first}-{last} = {size_mb:.1f} MB")
    check("derived extent differs from build-usb.sh's hardcoded 24.04.2 values",
          (first, last) != (6264708, 6274851),
          "would have been a silent UEFI-only failure")
    volid = s0.iso_volume_id(iso)
    check("volume id read from the PVD", bool(volid), volid)
    print(f"       ESP {first}d-{last}d ({size_mb:.1f} MB), volid {volid!r}")


def test_grub(tmp: Path):
    print("V5 — grub.cfg patching")
    stock = """set timeout=30
menuentry "Try or Install Ubuntu Server" {
\tset gfxpayload=keep
\tlinux\t/casper/vmlinuz  ---
\tinitrd\t/casper/initrd
}
menuentry "Ubuntu Server with the HWE kernel" {
\tlinux\t/casper/hwe-vmlinuz  ---
\tinitrd\t/casper/hwe-initrd
}
"""
    p = tmp / "grub.cfg"
    p.write_text(stock)
    n = s0.patch_grub(p, fake_config(hostname="offsite-01"))
    out = p.read_text()

    check("patched the casper boot line", n == 1, f"patched {n}")
    check("autoinstall on the kernel cmdline", "autoinstall" in out)
    check("nocloud datasource points at the stick",
          "s=/cdrom/nocloud/" in out)
    check("semicolon escaped for grub's parser", "ds=nocloud\\;" in out)
    check("params sit before the --- separator",
          out.count("---") == 2 and "nocloud/ ---" in out)
    check("menu entry renamed", "Autoinstall Sudhanix stage 0 (offsite-01)" in out)
    check("timeout shortened", "set timeout=5" in out)
    check("re-patching is idempotent",
          s0.patch_grub(p, fake_config()) == 0)


def test_timezone():
    print("V7 — timezone canonicalisation (crashed subiquity 2026-08-06)")
    check("legacy US/Pacific rewrites to the canonical zone",
          s0.canonical_timezone("US/Pacific") == "America/Los_Angeles")
    check("canonical zone passes through untouched",
          s0.canonical_timezone("America/Los_Angeles") == "America/Los_Angeles")
    check("geoip and empty are still allowed",
          s0.canonical_timezone("geoip") == "geoip"
          and s0.canonical_timezone("") == "")
    for bad in ("Mars/Olympus", "Pacific", "Canada/Eastern"):
        try:
            s0.canonical_timezone(bad)
            check(f"rejects {bad!r}", False, "it was accepted")
        except SystemExit:
            check(f"rejects {bad!r}", True)

    # The role default feeds the campus PXE templates too; it must be canonical.
    tz = s0.role_defaults().get("ni_timezone")
    check("role default ni_timezone is canonical",
          tz == s0.canonical_timezone(tz), f"ni_timezone={tz!r}")


def test_assets():
    print("V8 — --with-assets bundling")
    plain = fake_config()
    seed = yaml.safe_load(s0.render_seed(plain))["autoinstall"]
    check("no asset copy when --with-assets is absent",
          not any("sudhanix-assets" in str(c)
                  for c in seed.get("late-commands", [])))

    with_assets = fake_config(assets_dir=Path("/tmp/fake-assets"))
    ai = yaml.safe_load(s0.render_seed(with_assets))["autoinstall"]
    cmds = [str(c) for c in ai.get("late-commands", [])]
    check("asset copy emitted as a late-command",
          any("/cdrom/sudhanix-assets" in c and "/target/opt/sudhanix-assets" in c
              for c in cmds), str(cmds))
    check("banner survives alongside the asset copy",
          any("LOGIN_PLAIN_PROMPT" in c for c in cmds))

    # Assets with --no-banner must still produce a valid late-commands block,
    # not an orphaned key: that combination had no coverage before.
    solo = fake_config(assets_dir=Path("/tmp/fake-assets"), banner="")
    ai = yaml.safe_load(s0.render_seed(solo))["autoinstall"]
    check("assets alone still yield a well-formed late-commands list",
          isinstance(ai.get("late-commands"), list)
          and len(ai["late-commands"]) == 1)

    check("a missing asset dir is refused at build time",
          _refuses(lambda: s0.resolve_assets("/nonexistent/assets")))


def _refuses(fn):
    try:
        fn()
        return False
    except SystemExit:
        return True


def test_dd_portability():
    print("V6 — dd argument portability")
    src = TOOL.read_text()
    # GNU coreutils dd (Homebrew gnubin) shadows BSD dd on this workstation and
    # rejects "bs=4m" outright. Byte counts work under both.
    suffixed = re.findall(r"bs=\d+[a-zA-Z]", src)
    check("no lowercase-suffix bs= anywhere in the tool",
          not suffixed, f"found {suffixed}")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--iso", default=str(
        REPO_ROOT / "build" / "autoinstall-usb" / "ubuntu-24.04.4-live-server-amd64.iso"))
    args = ap.parse_args()

    tmp = Path(__file__).parent / ".work"
    tmp.mkdir(exist_ok=True)

    test_seed()
    test_gpt(Path(args.iso))
    test_grub(tmp)
    test_timezone()
    test_assets()
    test_dd_portability()

    for f in tmp.iterdir():
        f.unlink()
    tmp.rmdir()

    print()
    if FAILURES:
        print(f"FAILED ({len(FAILURES)}): " + ", ".join(FAILURES))
        sys.exit(1)
    print("All acceptance checks passed.")


if __name__ == "__main__":
    main()
