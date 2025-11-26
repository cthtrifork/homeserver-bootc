# `/etc/profile.d` Numbering Convention

## Numbering Scheme

### **00–09 — Very Early Environment Setup**
- Low-level initialization
- Locale fallbacks
- Minimal environment variables required before anything else

### **10–49 — Core System-Wide Environment**
- Standard distro-provided environment scripts
- PATH definitions
- Core variables needed by most tools

### **50–69 — Standard Application Environment**
- Application-level environment files
- Shell completions
- Language/tool-specific environment config (gawk, nano, debuginfod, etc.)

### **70–79 — System-Provided Shell Extras**
- Advanced but distro-managed scripts
- systemd shell extras
- Toolbox / OSC console helpers

### **80–89 — Site-Specific or Admin-Defined Configuration**
- Organization-wide settings
- Shared configuration for fleets or clusters
- Policies such as proxy, registry auth, SOPS, etc.

### **90–99 — Final Overrides / Local Machine Tweaks**
- Per-host customizations
- Settings intentionally loaded last
- Local overrides that must apply after all others
- Example: GNOME extension enablement (`93-gnome-extensions.sh`)
