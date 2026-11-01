#!/usr/bin/python3
"""Image build step: validate the egress allowlist and derive everything that consumes it.

usage: egress_allowlist.py ALLOWLIST MANAGED_SETTINGS_JSON OUTDIR

ALLOWLIST is one domain per line ("#" comments). A domain covers itself and all its subdomains. The build fails
(exit 1, every problem reported with its line number) on a wildcard, uppercase, IP literal, port, bare name, bad
label, duplicate, or an entry already covered by a parent (e.g. api.github.com next to github.com).

Writes:
  MANAGED_SETTINGS_JSON  .sandbox.network.allowedDomains = ["d", "*.d", ...] for every entry (other keys kept)
  OUTDIR/allowlist.txt   the sorted list
  OUTDIR/nginx-allow.map ".d  1;" lines, included by /usr/share/claude-vm/egress-nginx.conf ("hostnames" map)
  OUTDIR/dnsmasq-servers "server=/d/RESOLVER" lines, included by /usr/share/claude-vm/egress-dnsmasq.conf
"""

import argparse
import json
import re
import sys
from pathlib import Path

# systemd-resolved stub; the proxy and dnsmasq are not subject to the agent's firewall rules (see egress.nft)
RESOLVER = "127.0.0.53"

LABEL = r"[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?"
DOMAIN_RE = re.compile(rf"^{LABEL}(?:\.{LABEL})+$")
NUMERIC_RE = re.compile(r"^[0-9.]+$")  # IPv4 literals are not hostnames
MAX_NAME = 253


class AllowlistError(Exception):
    """The allowlist is not valid; args[0] is the list of messages."""


def parse(text: str) -> list[tuple[int, str]]:
    """(line number, entry) for every non-empty, non-comment line."""
    entries = []
    for number, line in enumerate(text.splitlines(), start=1):
        entry = line.split("#", 1)[0].strip()
        if entry:
            entries.append((number, entry))
    return entries


def validate(entries: list[tuple[int, str]]) -> list[str]:
    """All problems with the entries, as messages; empty when the list is valid."""
    if not entries:
        return ["empty allowlist"]
    problems = []
    first_seen: dict[str, int] = {}
    for number, domain in entries:
        if len(domain) > MAX_NAME or not DOMAIN_RE.match(domain) or NUMERIC_RE.match(domain):
            problems.append(
                f"line {number}: invalid entry '{domain}' "
                "(lowercase hostname with at least two labels; no wildcard, port, path or IP)"
            )
        elif domain in first_seen:
            problems.append(f"line {number}: duplicate of line {first_seen[domain]} ('{domain}')")
        else:
            first_seen[domain] = number
    for domain, number in first_seen.items():
        labels = domain.split(".")
        for i in range(1, len(labels) - 1):
            parent = ".".join(labels[i:])
            if parent in first_seen:
                problems.append(
                    f"line {number}: '{domain}' is already covered by '{parent}' (line {first_seen[parent]})"
                )
                break
    return problems


def merge_settings(settings: dict, domains: list[str]) -> dict:
    """Set sandbox.network.allowedDomains ("d" and "*.d" per entry), keeping every other key."""
    allowed = [name for domain in domains for name in (domain, f"*.{domain}")]
    settings.setdefault("sandbox", {}).setdefault("network", {})["allowedDomains"] = allowed
    return settings


def build(allowlist: Path, settings_path: Path, outdir: Path) -> list[str]:
    """Validate and write everything; returns the sorted domains. Raises AllowlistError."""
    entries = parse(allowlist.read_text())
    problems = validate(entries)
    if problems:
        raise AllowlistError(problems)
    domains = sorted(domain for _, domain in entries)

    settings = merge_settings(json.loads(settings_path.read_text()), domains)
    settings_path.write_text(json.dumps(settings, indent=2) + "\n")

    outdir.mkdir(parents=True, exist_ok=True)
    (outdir / "allowlist.txt").write_text("".join(f"{d}\n" for d in domains))
    (outdir / "nginx-allow.map").write_text("".join(f".{d}  1;\n" for d in domains))
    (outdir / "dnsmasq-servers").write_text("".join(f"server=/{d}/{RESOLVER}\n" for d in domains))
    return domains


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    parser.add_argument("allowlist", type=Path)
    parser.add_argument("managed_settings", type=Path, metavar="managed-settings.json")
    parser.add_argument("outdir", type=Path)
    args = parser.parse_args(argv)
    try:
        domains = build(args.allowlist, args.managed_settings, args.outdir)
    except AllowlistError as error:
        for problem in error.args[0]:
            print(f"{args.allowlist}: {problem}", file=sys.stderr)
        return 1
    print(f"egress-allowlist: {len(domains)} domains")
    return 0


if __name__ == "__main__":
    sys.exit(main())
