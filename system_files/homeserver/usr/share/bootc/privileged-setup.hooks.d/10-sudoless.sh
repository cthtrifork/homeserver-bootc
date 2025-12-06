TARGET_USER="$(getent passwd "$PKEXEC_UID" | cut -d: -f1)"

echo "Configuring subuid/subgid for $TARGET_USER"

touch /etc/subuid /etc/subgid
usermod --add-subuid 100000-165535 --add-subgid 100000-165535 $TARGET_USER