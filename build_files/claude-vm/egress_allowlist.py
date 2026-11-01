#!/usr/bin/python3
"""Validate the egress allowlist and derive the sandbox, nginx and dnsmasq lists from it.

usage: egress_allowlist.py ALLOWLIST MANAGED_SETTINGS_JSON OUTDIR
"""

import argparse
import json
import re
import sys
from pathlib import Path

RESOLVER = "127.0.0.53"  # systemd-resolved stub

LABEL = r"[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?"
DOMAIN_RE = re.compile(rf"^{LABEL}(?:\.{LABEL})+$")
NUMERIC_RE = re.compile(r"^[0-9.]+$")
MAX_NAME = 253


def parse(text):
    entries = []
    for number, line in enumerate(text.splitlines(), start=1):
        entry = line.split("#", 1)[0].strip()
        if entry:
            entries.append((number, entry))
    return entries


def validate(entries):
    if not entries:
        return ["empty allowlist"]
    problems = []
    first_seen = {}
    for number, domain in entries:
        if len(domain) > MAX_NAME or not DOMAIN_RE.match(domain) or NUMERIC_RE.match(domain):
            problems.append(f"line {number}: invalid entry '{domain}'")
        elif domain in first_seen:
            problems.append(f"line {number}: duplicate of line {first_seen[domain]} ('{domain}')")
        else:
            first_seen[domain] = number
    for domain, number in first_seen.items():
        labels = domain.split(".")
        for i in range(1, len(labels) - 1):
            parent = ".".join(labels[i:])
            if parent in first_seen:
                problems.append(f"line {number}: '{domain}' is already covered by '{parent}'")
                break
    return problems


def build(allowlist, settings_path, outdir):
    entries = parse(allowlist.read_text())
    problems = validate(entries)
    if problems:
        raise SystemExit("\n".join(f"{allowlist}: {p}" for p in problems))
    domains = sorted(domain for _, domain in entries)

    settings = json.loads(settings_path.read_text())
    settings.setdefault("sandbox", {}).setdefault("network", {})["allowedDomains"] = [
        name for d in domains for name in (d, f"*.{d}")
    ]
    settings_path.write_text(json.dumps(settings, indent=2) + "\n")

    outdir.mkdir(parents=True, exist_ok=True)
    (outdir / "allowlist.txt").write_text("".join(f"{d}\n" for d in domains))
    (outdir / "nginx-allow.map").write_text("".join(f".{d}  1;\n" for d in domains))
    (outdir / "dnsmasq-servers").write_text("".join(f"server=/{d}/{RESOLVER}\n" for d in domains))
    return domains


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("allowlist", type=Path)
    parser.add_argument("managed_settings", type=Path)
    parser.add_argument("outdir", type=Path)
    args = parser.parse_args()
    domains = build(args.allowlist, args.managed_settings, args.outdir)
    print(f"egress-allowlist: {len(domains)} domains")


if __name__ == "__main__":
    main()
