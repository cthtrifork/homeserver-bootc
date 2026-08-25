#!/usr/bin/env bash
# todo: move to system_files/homeserver/usr/lib/tmpfiles.d/link-podman-credentials.conf ?
cp /run/secrets/creds /usr/lib/container-auth.json
chmod 0600 /usr/lib/container-auth.json
# For rpm-ostree / bootc / ostree-container pulls
ln -sf /usr/lib/container-auth.json /etc/ostree/auth.json
# For podman/skopeo/buildah (root context)
mkdir -p /etc/containers && \
ln -sf /usr/lib/container-auth.json /etc/containers/auth.json
# For docker CLI (real Docker or the podman-docker shim): per-daemon fallback
mkdir -p /etc/docker && \
ln -sf /usr/lib/container-auth.json /etc/docker/config.json
