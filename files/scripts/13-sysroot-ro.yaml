#!/usr/bin/env bash
set -xeuo pipefail

install -dm 0755 -o 0 -g 0 /usr/lib/ostree
cat >> /usr/lib/ostree/prepare-root.conf << 'EOF'
[sysroot]
readonly = true
EOF
