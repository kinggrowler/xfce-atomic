#!/bin/bash

set -euo pipefail

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
