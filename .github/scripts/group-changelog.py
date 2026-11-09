#!/usr/bin/env python3
"""Fill the <!--COMMITS--> marker of a rechunk changelog with commits grouped by the part of the repo they touch.

rechunk lists every commit since the previous image, and all images are built from one repo, so each image's
changelog would show the others' commits. This groups them by the files they change instead: the image's own
groups are shown, everything else is folded into a <details> block.

Env: IMAGE (homeserver|homeserver-gui|claude-vm), REPO_URL, GITHUB_SHA (or HEAD_REV)
     MANIFEST   skopeo inspect output of the previous image (default previous.manifest.json)
     PREV_REV   previous revision, overrides the label in MANIFEST (for local dry runs)
Usage: group-changelog.py <changelog.md>
"""
import json
import os
import re
import subprocess
import sys

REVISION_LABEL = "org.opencontainers.image.revision"
MARKER = "<!--COMMITS-->"

# name -> path prefixes (a prefix ending in / matches a directory, otherwise an exact path). A commit is listed
# under every group it touches; a commit touching none lands in "Other".
GROUPS = {
    "Homeserver": ["homeserver.containerfile", "system_files/homeserver/", "tests/homeserver/"],
    "Homeserver GUI": ["homeserver-gui.containerfile", "system_files/homeserver-gui/", "build_files/gui/",
                       "tests/homeserver-gui/"],
    "Claude VM": ["claude-vm.containerfile", "system_files/claude-vm/", "build_files/claude-vm/",
                  "build_files/claude-vm-utilities.sh", "docs/claude-vm/", "tests/claude-vm/"],
    "Shared build": ["build_files/"],  # matched last, after the image specific build_files above
    "CI and repo": [".github/", "README.md", "docs/", "tests/", "renovate.json5"],
}
# Groups shown in full per image; the rest is folded away. GUI is homeserver plus extras.
SHOWN = {
    "homeserver": ["Homeserver", "Shared build"],
    "homeserver-gui": ["Homeserver GUI", "Homeserver", "Shared build"],
    "claude-vm": ["Claude VM", "Shared build"],
}
# paths that also fall under a broader group but belong to one image only
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
    """[(short, full, subject, {files})] newest first, merges excluded like rechunk does."""
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
            # e.g. the previous revision is older than the checkout depth; keep the release going
            print(f"::warning::git log {prev}..{head} failed: {e.stderr.strip().splitlines()[0]}")
            sections, body = {}, f"Could not list commits since `{prev[:7]}` (not in the checkout)."
        else:
            shown = [f"#### {n}\n{sections[n]}" for n in SHOWN[image] if n in sections]
            other = [f"#### {n}\n{t}" for n, t in sections.items() if n not in SHOWN[image]]
            body = "\n\n".join(shown) or "No changes for this image."
            if other:
                body += ("\n\n<details><summary>Other images, CI and unlisted paths</summary>\n\n"
                         + "\n\n".join(other) + "\n\n</details>")

    text = open(path).read()
    if MARKER not in text:
        sys.exit(f"{MARKER} not found in {path}")
    open(path, "w").write(text.replace(MARKER, body))


if __name__ == "__main__":
    main()
