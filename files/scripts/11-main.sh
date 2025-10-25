#!/bin/bash

set -ouex pipefail

# Not sure why we need this, but here it is
echo "KillUserProcesses=yes" >>/usr/lib/systemd/logind.conf

# this tool from winblues no longer works, erroring with:
# Error initializing Xfconf: xml: unsupported version "1.1"; only version 1.0 is supported
#curl -L -o /usr/bin/xfconf-profile https://github.com/winblues/xfconf-profile/releases/latest/download/xfconf-profile-linux-amd64
#chmod +x /usr/bin/xfconf-profile

gem install fusuma --no-document --install-dir /usr/lib/ruby/gems/fusuma
ln -s /usr/lib/ruby/gems/fusuma/bin/fusuma /usr/bin/fusuma

dnf5 -y install --nogpgcheck --repofrompath 'terra,https://repos.fyralabs.com/terra$releasever' terra-release{,-extras}
dnf5 -y install flatpost
dnf5 -y install firacode-nerd-fonts
dnf5 -y install nerdfontssymbolsonly-nerd-fonts
dnf5 -y config-manager setopt "terra*".enabled=false
