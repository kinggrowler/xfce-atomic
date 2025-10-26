# Originally from common.yaml file

#!/bin/bash

set -ouex pipefail


# Work around https://bugzilla.redhat.com/show_bug.cgi?id=1265295
# From https://github.com/coreos/fedora-coreos-config/blob/testing-devel/overlay.d/05core/usr/lib/systemd/journald.conf.d/10-coreos-persistent.conf
install -dm0755 /usr/lib/systemd/journald.conf.d/
echo -e "[Journal]\nStorage=persistent" > /usr/lib/systemd/journald.conf.d/10-persistent.conf

# See: https://src.fedoraproject.org/rpms/glibc/pull-request/4
# Basically that program handles deleting old shared library directories
# mid-transaction, which never applies to rpm-ostree. This is structured as a
# loop/glob to avoid hardcoding (or trying to match) the architecture.
for x in /usr/sbin/glibc_post_upgrade.*; do
    if test -f ${x}; then
        ln -srf /usr/bin/true ${x}
    fi
done

# Remove loader directory causing issues in Anaconda in unified core mode
# Will be obsolete once we start using bootupd
rm -rf /usr/lib/ostree-boot/loader

# Undo RPM scripts enabling units; we want the presets to be canonical
# https://github.com/projectatomic/rpm-ostree/issues/1803
rm -rf /etc/systemd/system/*
systemctl preset-all
rm -rf /etc/systemd/user/*
systemctl --user --global preset-all

# Fix triggerin for samba-client in cups package (not supported by rpm-ostree yet)
# https://github.com/fedora-silverblue/issue-tracker/issues/532
ln -snf /usr/libexec/samba/cups_backend_smb /usr/lib/cups/backend/smb

