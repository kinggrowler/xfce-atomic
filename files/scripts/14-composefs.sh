# Enable composefs
# See: https://fedoraproject.org/wiki/Changes/ComposefsAtomicDesktops

#!/usr/bin/env bash

set -xeuo pipefail

cat > /usr/lib/ostree/prepare-root.conf << 'EOF'
[composefs]
enabled = yes
EOF
