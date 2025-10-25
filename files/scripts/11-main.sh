#!/bin/bash
set -xeuo pipefail

dnf5 -y install bootupd

# Transforms /usr/lib/ostree-boot into a bootupd-compatible update payload
/usr/bin/bootupctl backend generate-update-metadata

# Enable migration to a static GRUB config
install -dm0755 /usr/lib/systemd/system/bootloader-update.service.d
cat > /usr/lib/systemd/system/bootloader-update.service.d/migrate-static-grub-config.conf << 'EOF'
[Service]
ExecStart=/usr/bin/bootupctl migrate-static-grub-config
EOF

echo "enable bootloader-update.service" > /usr/lib/systemd/system-preset/81-atomic-desktop.preset

# Turn permissive mode on for bootupd until all SELinux issues are fixed
semanage permissive --noreload --add bootupd_t
