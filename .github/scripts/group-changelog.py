#!/usr/bin/env python3
"""Fill the <!--COMMITS--> marker of a changelog with commits grouped by the files they touch.

Env: PACKAGES (rpm list, tab separated), IMAGE, REPO_URL, GITHUB_SHA (or HEAD_REV); MANIFEST (default previous.manifest.json); PREV_REV overrides its label.
Usage: group-changelog.py <changelog.md>
"""
import base64
import gzip
import json
import os
import re
import subprocess
import sys

REVISION_LABEL = "org.opencontainers.image.revision"
MARKER = "<!--COMMITS-->"
PKG_MARKER = "<!--PACKAGES-->"
PKG_LABEL = "org.homeserver.rpm-packages"
# placeholders like <version:pkg> are dropped when left unresolved
UNRESOLVED = re.compile(r"^.*<version:[^>]*>.*\n", re.M)

# a prefix ending in / matches a directory, anything else an exact path
GROUPS = {
    "Homeserver": ["homeserver.containerfile", "system_files/homeserver/", "tests/homeserver/"],
    "Homeserver GUI": ["homeserver-gui.containerfile", "system_files/homeserver-gui/", "build_files/gui/",
                       "tests/homeserver-gui/"],
    "Claude VM": ["claude-vm.containerfile", "system_files/claude-vm/", "build_files/claude-vm/",
                  "build_files/claude-vm-utilities.sh", "docs/claude-vm/", "tests/claude-vm/"],
    "Shared build": ["build_files/"],
    "CI and repo": [".github/", "README.md", "docs/", "tests/", "renovate.json5"],
}
# the GUI image is homeserver plus extras
SHOWN = {
    "homeserver": ["Homeserver", "Shared build"],
    "homeserver-gui": ["Homeserver GUI", "Homeserver", "Shared build"],
    "claude-vm": ["Claude VM", "Shared build"],
}
OWN_BUILD = ("build_files/gui/", "build_files/claude-vm/", "build_files/claude-vm-utilities.sh")
OWN_DOCS_TESTS = ("docs/claude-vm/", "tests/homeserver/", "tests/homeserver-gui/", "tests/claude-vm/")
DEPS = re.compile(r"^chore\(deps\)")


def groups_of(path):
    found = set()
    for name, prefixes in GROUPS.items():
        for p in prefixes:
            if path == p or (p.endswith("/") and path.startswith(p)):
                if name == "Shared build" and path.startswith(OWN_BUILD):
                    continue
                if name == "CI and repo" and path.startswith(OWN_DOCS_TESTS):
                    continue
                found.add(name)
    return found


def git_log(prev, head):
    out = subprocess.run(
        ["git", "log", "--no-merges", "--name-only", "--format=%x00%h%x09%H%x09%s", f"{prev}..{head}"],
        capture_output=True, text=True, check=True,
    ).stdout
    commits = []
    for chunk in out.split("\0")[1:]:
        head_line, _, files = chunk.partition("\n")
        short, full, subject = head_line.split("\t", 2)
        commits.append((short, full, subject, {f for f in files.split("\n") if f}))
    return commits


def render(commits, repo):
    def line(c):
        return f"- **[{c[0]}]({repo}/commit/{c[1]})** {c[2]}"

    def block(items):
        deps = [c for c in items if DEPS.match(c[2])]
        text = "\n".join(line(c) for c in items if c not in deps)
        if deps:
            text += (f"\n\n<details><summary>{len(deps)} dependency updates</summary>\n\n"
                     + "\n".join(line(c) for c in deps) + "\n\n</details>")
        return text.strip()

    by_group = {name: [] for name in [*GROUPS, "Other"]}
    for c in commits:
        names = set().union(*(groups_of(f) for f in c[3])) or {"Other"}
        for n in names:
            by_group[n].append(c)
    return {n: block(items) for n, items in by_group.items() if items}


def read_packages(text):
    return dict(line.split("\t", 1) for line in text.splitlines() if "\t" in line)


def package_changes(manifest, current_file):
    """Diff the current package list (PACKAGES file) with the one stored as a label on the previous image."""
    try:
        old_label = json.load(open(manifest)).get("Labels", {}).get(PKG_LABEL)
        new = read_packages(open(current_file).read())
    except (OSError, ValueError):
        return "No package list available."
    if not old_label:
        return "No package list on the previous image, so no package diff."
    old = read_packages(gzip.decompress(base64.b64decode(old_label)).decode())
    lines = [f"- **{n}** Added at {new[n]}" for n in sorted(new.keys() - old.keys())]
    lines += [f"- **{n}** {old[n]} → {new[n]}" for n in sorted(new.keys() & old.keys()) if old[n] != new[n]]
    lines += [f"- **{n}** {old[n]} → Removed" for n in sorted(old.keys() - new.keys())]
    return "\n".join(lines) or "No package updates"


def main():
    path = sys.argv[1]
    image, repo = os.environ["IMAGE"], os.environ["REPO_URL"]
    head = os.environ.get("HEAD_REV") or os.environ["GITHUB_SHA"]
    manifest = os.environ.get("MANIFEST", "previous.manifest.json")
    prev = os.environ.get("PREV_REV") or json.load(open(manifest)).get("Labels", {}).get(REVISION_LABEL, "")

    if not prev:
        body = "No previous revision (first build of this image?), so no commit list."
    else:
        try:
            sections = render(git_log(prev, head), repo)
        except subprocess.CalledProcessError as e:
            print(f"::warning::git log {prev}..{head} failed: {e.stderr.strip().splitlines()[0]}")
            sections, body = {}, f"Could not list commits since `{prev[:7]}` (not in the checkout)."
        else:
            shown = [f"#### {n}\n\n{sections[n]}" for n in SHOWN[image] if n in sections]
            other = [f"#### {n}\n\n{t}" for n, t in sections.items() if n not in SHOWN[image]]
            body = "\n\n".join(shown) or "No changes for this image."
            if other:
                body += ("\n\n<details><summary>Other images, CI and unlisted paths</summary>\n\n"
                         + "\n\n".join(other) + "\n\n</details>")

    text = open(path).read()
    if MARKER not in text:
        sys.exit(f"{MARKER} not found in {path}")
    text = text.replace(MARKER, body)
    if PKG_MARKER in text:
        text = text.replace(PKG_MARKER, package_changes(manifest, os.environ.get("PACKAGES", "packages.tsv")))
    open(path, "w").write(UNRESOLVED.sub("", text))


if __name__ == "__main__":
    main()
