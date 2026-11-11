#!/usr/bin/env python3
"""Set the creation time of a single-manifest OCI layout (the chunkah output) without touching its layers.

chunkah uses SOURCE_DATE_EPOCH for both the file mtimes in the layers and the image's `created` time. The workflow
pins the epoch so unchanged packages give identical layers, which leaves `created` (and every history entry) at 1970.
This rewrites only the config blob, the manifest and the index, so the layer digests stay as they are.

Usage: set-image-created.py <oci-layout-dir> <RFC 3339 timestamp>
"""
import hashlib
import json
import os
import sys


def write_blob(root, data):
    digest = hashlib.sha256(data).hexdigest()
    path = os.path.join(root, "blobs", "sha256", digest)
    with open(path, "wb") as f:
        f.write(data)
    return {"digest": f"sha256:{digest}", "size": len(data)}


def blob_path(root, digest):
    return os.path.join(root, "blobs", digest.replace(":", "/", 1))


def main():
    root, created = sys.argv[1], sys.argv[2]
    index = json.load(open(os.path.join(root, "index.json")))
    if len(index["manifests"]) != 1:
        sys.exit("expected exactly one manifest in index.json")
    old_manifest = index["manifests"][0]
    manifest = json.load(open(blob_path(root, old_manifest["digest"])))
    old_config_digest = manifest["config"]["digest"]
    config = json.load(open(blob_path(root, old_config_digest)))

    config["created"] = created
    for entry in config.get("history", []):
        entry["created"] = created

    manifest["config"].update(write_blob(root, json.dumps(config, separators=(",", ":")).encode()))
    old_manifest_digest = old_manifest["digest"]
    old_manifest.update(write_blob(root, json.dumps(manifest, separators=(",", ":")).encode()))
    json.dump(index, open(os.path.join(root, "index.json"), "w"), separators=(",", ":"))

    for digest in (old_config_digest, old_manifest_digest):
        os.remove(blob_path(root, digest))
    print(f"created={created} manifest={old_manifest['digest']}")


if __name__ == "__main__":
    main()
