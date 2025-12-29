#!/bin/bash

set -euo pipefail

# let's barf if key packages aren't installed, indicated
# something failed along the way.

packages=("mousepad" "xfce4-terminal" "fedora-release-xfce")

missing=()
for pkg in "${packages[@]}"; do
  if ! rpm -q --quiet "$pkg"; then
    missing+=("$pkg")
  fi
done

if ((${#missing[@]} > 0)); then
  echo "The following packages are missing: ${missing[*]}"
  exit 1
fi
