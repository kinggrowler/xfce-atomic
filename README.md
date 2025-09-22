# Experimental Ostree Native Container images for rpm-ostree based Fedora desktop variants

## Overview

This repo is a fork of
[pagure.io/workstation-ostree-config](https://pagure.io/workstation-ostree-config)
with CI and minor changes on top to enable us to build Bootable Container
images for the Fedora Atomic Desktops.

The offcial upstream sources for Fedora Silverblue, Fedora Kinoite, Fedora Sway
Atomic, Fedora Budgie Atomic and Fedora COSMIC Atomic remain at
[pagure.io/workstation-ostree-config](https://pagure.io/workstation-ostree-config)
and the official builds are only available from the Fedora ostree repo for now.

See the [Roadmap to Fedora Bootable Containers](https://gitlab.com/fedora/ostree/sig/-/issues/26)
for the work in progress to switch the Fedora Atomic Desktops to Bootable Containers.

## Issues and PRs

Please submit PRs at
[pagure.io/workstation-ostree-config](https://pagure.io/workstation-ostree-config)
and file issues in the respective projects issue trackers:

- For issues impacting all Atomic desktop variants: [Fedora Atomic Desktops issue tracker](https://gitlab.com/fedora/ostree/sig/-/issues)
- For Fedora Silverblue specific issues: [github.com/fedora-silverblue/issue-tracker](https://github.com/fedora-silverblue/issue-tracker/issues)
- For Fedora Kinoite specific issues: [pagure.io/fedora-kde/SIG](https://pagure.io/fedora-kde/SIG/issues)
- For Fedora Sway Atomic specific issues: [gitlab.com/fedora/sigs/sway/SIG](https://gitlab.com/fedora/sigs/sway/SIG/-/issues)
- For Fedora Budgie Atomic specific issues: [pagure.io/fedora-budgie](https://pagure.io/fedora-budgie/project/issues)
- For Fedora COSMIC Atomic specific issues: [pagure.io/fedora-cosmic/SIG](https://pagure.io/fedora-cosmic/SIG/issues)

## Images built

This project builds the following images for all Fedora releases:

- Fedora Silverblue:
    - Unofficial build based on the official Silverblue variant
    - [quay.io/repository/fedora-ostree-desktops/silverblue](https://quay.io/repository/fedora-ostree-desktops/silverblue?tab=tags)
- Fedora Kinoite:
    - Unofficial build based on the official Kinoite variant
    - [quay.io/repository/fedora-ostree-desktops/kinoite](https://quay.io/repository/fedora-ostree-desktops/kinoite?tab=tags)
- Fedora Sway Atomic:
    - Unofficial build based on the official Sway Atomic variant
    - [quay.io/repository/fedora-ostree-desktops/sway-atomic](https://quay.io/repository/fedora-ostree-desktops/sway-atomic?tab=tags)
- Fedora Budgie Atomic:
    - Unofficial build based on the official Budgie Atomic variant
    - [quay.io/repository/fedora-ostree-desktops/budgie-atomic](https://quay.io/repository/fedora-ostree-desktops/budgie-atomic?tab=tags)
- Fedora COSMIC Atomic:
    - Unofficial build based on the official COSMIC Atomic variant
    - [quay.io/repository/fedora-ostree-desktops/cosmic-atomic](https://quay.io/repository/fedora-ostree-desktops/cosmic-atomic?tab=tags)
- Fedora Base Atomic:
    - Minimal image with no desktop environment
    - [quay.io/repository/fedora-ostree-desktops/base-atomic](https://quay.io/repository/fedora-ostree-desktops/base-atomic?tab=tags)

Special images that may not always be available,
(see [Introducing Kinoite Nightly (and Kinoite Beta)](https://tim.siosm.fr/blog/2023/01/20/introducing-kinoite-nightly-beta/)):

- Fedora Kinoite Nightly:
    - Unofficial Kinoite variant with nightly KDE packages from [solopasha's COPRs](https://github.com/solopasha/kde6-copr)
    - [quay.io/repository/fedora-ostree-desktops/kinoite-nightly](https://quay.io/repository/fedora-ostree-desktops/kinoite-nightly?tab=tags)
- Fedora Kinoite Beta:
    - On hold right now
<!--    - Unofficial Kinoite variant with KDE Plasma Beta packages from [@kdesig/kde-beta](https://copr.fedorainfracloud.org/coprs/g/kdesig/kde-beta/) -->
<!--    - [quay.io/repository/fedora-ostree-desktops/kinoite-beta](https://quay.io/repository/fedora-ostree-desktops/kinoite-beta?tab=tags) -->

Other images no longer built starting with Fedora 43 due to lack of users and
help with maintenance:

- Fedora LXQt Atomic:
    - Unofficial LXQt variant
    - [quay.io/repository/fedora-ostree-desktops/lxqt-atomic](https://quay.io/repository/fedora-ostree-desktops/lxqt-atomic?tab=tags)
- Fedora XFCE Atomic:
    - Unofficial XFCE variant
    - [quay.io/repository/fedora-ostree-desktops/xfce-atomic](https://quay.io/repository/fedora-ostree-desktops/xfce-atomic?tab=tags)

## Setup container image signature verification

- Get the public key from this repo and install it:

  ```
  $ sudo mkdir /etc/pki/containers
  $ curl -O "https://gitlab.com/fedora/ostree/ci-test/-/raw/main/quay.io-fedora-ostree-desktops.pub?ref_type=heads&inline=false"
  $ sudo cp quay.io-fedora-ostree-desktops.pub /etc/pki/containers/
  $ sudo restorecon -RFv /etc/pki/containers
  $ rm quay.io-fedora-ostree-desktops.pub
  ```

- Add registry configuration to get sigstore signatures:

  ```
  $ cat /etc/containers/registries.d/quay.io-fedora-ostree-desktops.yaml
  docker:
    quay.io/fedora-ostree-desktops:
      use-sigstore-attachments: true
  $ sudo restorecon -RFv /etc/containers/registries.d
  ```

- Add config to the container fetching policy:

  ```
  $ cat /etc/containers/policy.json
  {
      "default": [{ "type": "reject" }],
      "transports": {
          "docker": {
              "quay.io/fedora-ostree-desktops": [
                  {
                      "type": "sigstoreSigned",
                      "keyPath": "/etc/pki/containers/quay.io-fedora-ostree-desktops.pub",
                      "signedIdentity": {
                          "type": "matchRepository"
                      }
                  }
              ],
              "": [{ "type": "insecureAcceptAnything" }]
          },
          "containers-storage": {
              "": [{ "type": "insecureAcceptAnything" }]
          },
          "oci": {
              "": [{ "type": "insecureAcceptAnything" }]
          },
          "oci-archive": {
              "": [{ "type": "insecureAcceptAnything" }]
          },
          "docker-daemon": {
              "": [{ "type": "insecureAcceptAnything" }]
          }
      }
  }
  ```

- Rebase:

  ```
  $ sudo rpm-ostree rebase ostree-image-signed:registry:quay.io/fedora-ostree-desktops/silverblue:42
  ```

## Can I add an image here? How do I add my image?

In this repo, we will only build images from official Fedora RPM packages or
from COPR repos maintained by official Fedora SIGs.

File an issue in this repo if you want another desktop variant to be built.

In all other cases, you will have to host your own CI and images. Take a look
at the [Universal Blue project](https://universal-blue.org/) for examples.

If you want to maintain a new official image in Fedora, you can follow the
[How to add a new Fedora Atomic Desktop variant in Fedora?](https://tim.siosm.fr/blog/2023/06/21/rpm-ostree-variants-fedora/)
guide.
