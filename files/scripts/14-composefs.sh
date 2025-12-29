#!/usr/bin/env bash

set -xeuo pipefail

# Enable composefs
# See: https://fedoraproject.org/wiki/Changes/ComposefsAtomicDesktops

# this file is ALSO written to in script 13-sysroot-ro.sh
# so don't overwrite it!
cat >> /usr/lib/ostree/prepare-root.conf << 'EOF'
[composefs]
enabled = yes
EOF

