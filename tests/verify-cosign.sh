#!/usr/bin/env bash
set -euo pipefail

scopeo_verify() {
    cat > /tmp/policy-permissive.json <<'EOF'
    { "default": [{"type":"insecureAcceptAnything"}] }
EOF

    echo "Pulling image: ${IMAGE_FULL}:latest without signature verification"
    skopeo copy --policy /tmp/policy-permissive.json docker://${IMAGE_FULL}:latest dir:$(mktemp -d ${HOME}/tmp-image.XXXXXX)
    DIGEST=$(skopeo inspect --format "{{.Digest}}" docker://${IMAGE_FULL}:latest)
    echo "Manually verifying image signature for image: ${IMAGE_FULL}@${DIGEST}"
    cosign verify --key /etc/pki/cosign/cosign.pub ${IMAGE_FULL}@${DIGEST}
    echo "Image signature verified manually"
}

podman_pull_without_trust() {
    cat > /tmp/policy-permissive.json <<'EOF'
    { "default": [{"type":"insecureAcceptAnything"}] }
EOF
    echo "Pulling image: ${IMAGE_FULL}:latest without signature verification"
    podman pull --signature-policy /tmp/policy-permissive.json ${IMAGE_FULL}@latest
}

# The policy baked into the image must enforce signatures for our registry scope
grep -q '"sigstoreSigned"' /etc/containers/policy.json
grep -q 'ghcr.io/cthtrifork/homeserver-bootc"' /etc/containers/policy.json
echo "Signature policy is enforcing for ghcr.io/cthtrifork/homeserver-bootc"

#podman pull --log-level=debug ${IMAGE_FULL}:latest 2>&1 | grep -iE 'digest|signature|sigstore' || true
podman pull ${IMAGE_FULL}:latest

# Provenance attestation (actions/attest) is stored in the registry next to the image
DIGEST=$(skopeo inspect --format "{{.Digest}}" docker://${IMAGE_FULL}:latest)
echo "Verifying build provenance attestation for ${IMAGE_FULL}@${DIGEST}"
gh attestation verify "oci://${IMAGE_FULL}@${DIGEST}" --repo cthtrifork/homeserver-bootc
echo "Attestation verified"
