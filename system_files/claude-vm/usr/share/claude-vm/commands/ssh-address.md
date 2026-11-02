---
description: Show the SSH command for reaching this VM via the Pinggy tunnel
allowed-tools: Bash(claude-vm-ssh-address:*)
---
Run `claude-vm-ssh-address` and give me its output exactly.
If it prints "No tunnel address yet", tell me the tunnel isn't running and that I need to run `sudo systemctl enable --now claude-pinggy`.
