
#!/usr/bin/env bash

SOPS_AGE_KEY="$(cat /run/secrets/agekey)"
install -D -m 0600 /run/secrets/agekey /usr/lib/sops/age/keys.txt
chown root:root /usr/lib/sops/age/keys.txt
chmod 0640 /usr/lib/sops/age/keys.txt
printf "export SOPS_AGE_KEY=%s\n" "$SOPS_AGE_KEY" | tee /etc/profile.d/61-age-sops-private.sh 1>/dev/null
