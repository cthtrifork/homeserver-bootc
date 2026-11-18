# Image signing

The OS images (`ghcr.io/cthtrifork/homeserver-bootc/homeserver-bootc`, `homeserver-gui-bootc` and `claude-vm-bootc`, and the
`hello` test image) are signed with a cosign key pair when they are built on `main`. The hosts refuse an image of ours that is not
signed by it. The same scheme signs the images of
[github-runner-bootc](https://github.com/cthtrifork/github-runner-bootc/blob/main/docs/signing.md); keep the two in step.

Why a key and not keyless signing: the host checks signatures with podman's `policy.json`, and its keyless (Fulcio) rule only
accepts an email identity. A GitHub Actions certificate names a workflow, not an email, so it cannot be expressed there.

## How it works

- The `push-latest` job of `build-bootc-image.yaml` (never run for a pull request) signs the pushed digest with cosign **v3** in its
  legacy format (`--new-bundle-format=false` and `--registry-referrers-mode=legacy`), which writes the `sha256-<digest>.sig` tag that
  podman and bootc read. `--use-signing-config=false` keeps the explicit key-based signing and `--tlog-upload=false` skips the
  transparency log: the host needs no Rekor. The same flags sign the Trivy `vuln` attestation. `push-hello-containerfile.yaml`
  signs the `hello` image the same way, with `--recursive` because it pushes an index.
- The job fails when the key is not set, so a build never ships an image the hosts would reject.
- The private key is the secret `SIGNING_SECRET` (an unencrypted key, so `COSIGN_PASSWORD` is empty). A pull request build never
  runs the signing job and is not signed.
- The signature is a tag of the package, so `cleanup-old-images.yml` excludes `sha256-*` tags: deleting one would make the hosts refuse its image.
- cosign is pinned to the same version in the workflows (`cosign-release`) and in `build_files/core/09-utilities.sh`; Renovate
  updates them. Stay on v3 and keep the legacy-format flags: without them cosign writes a bundle that containers/image cannot read.

## Set it up (once)

1. On a machine you trust, with cosign v3: `cosign generate-key-pair`. It writes `cosign.key` and `cosign.pub`.
2. Add the contents of `cosign.key` as the secret `SIGNING_SECRET` and delete the local copy. The workflows pass an empty
   `COSIGN_PASSWORD`, so give the key an empty password, or add the password as a secret and use it there.
3. Commit `cosign.pub` (public) to the repository root. It is the key the host policy uses. Private keys are git-ignored.

## Check a signature

```sh
cosign verify --key cosign.pub --new-bundle-format=false --insecure-ignore-tlog=true ghcr.io/cthtrifork/homeserver-bootc/homeserver-bootc:latest
```

The build verifies each signature (and the `vuln` attestation) right after signing. `tests/verify-cosign.sh` pulls the signed `hello` image on a booted VM, which enforces the policy, and checks its provenance attestation.

## On the hosts

Every image ships `cosign.pub` (`/etc/pki/cosign/cosign.pub`), `/etc/containers/policy.json` (the repository's `policy.json`) and
`/etc/containers/registries.d/ghcr.yaml` (`use-sigstore-attachments`, so the `.sig` tags are read). The policy requires a
`sigstoreSigned` signature from that key (`signedIdentity: matchRepository`, which is what cosign signatures can express) for
everything under `ghcr.io/cthtrifork/homeserver-bootc`, and accepts every other image. `bootc upgrade`, `bootc switch` and `podman pull`
all use it, so an unsigned image of ours, including an older tag from before signing, is refused with "A signature was required, but
no signature exists". The system tests (`tests/*/system-test.sh`, `tests/claude-vm/guard-tests.sh`) check that the policy, the key and
the registry config are in the image.

- A host moves to the first release with this policy under its old policy; from then on it enforces it.
- A site that mirrors the images under another registry name is not covered (the policy matches our repository names): copy the
  signatures with the images and add the same entries for the mirror.

## Rotating the key

Generate a new pair, put both public keys in the policy (`keyPaths`), release, then replace the secret and release again, then drop
the old public key.
