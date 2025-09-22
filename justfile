# This is a justfile. See https://github.com/casey/just
# This is only used for local development. The builds made on the Fedora
# infrastructure are run via Pungi in a Koji runroot.

# Set a default for some recipes
default_variant := "silverblue"
default_arch := "default"
# Current default in Pungi
force_nocache := "true"

# Just doesn't have a native dict type, but quoted bash dictionary works fine
pretty_names := '(
    [silverblue]="Silverblue"
    [kinoite]="Kinoite"
    [kinoite-nightly]="Kinoite"
    [kinoite-beta]="Kinoite"
    [kinoite-mobile]="Kinoite"
    [sway-atomic]="Sway Atomic"
    [budgie-atomic]="Budgie Atomic"
    [xfce-atomic]="XFCE Atomic"
    [lxqt-atomic]="LXQt Atomic"
    [base-atomic]="Base Atomic"
    [cosmic-atomic]="COSMIC Atomic"
)'

# subset of the map from https://pagure.io/pungi-fedora/blob/main/f/general.conf
volume_id_substitutions := '(
    [silverblue]="SB"
    [kinoite]="Kin"
    [kinoite-nightly]="Kin"
    [kinoite-beta]="Kin"
    [kinoite-mobile]="Kin"
    [sway-atomic]="SwA"
    [budgie-atomic]="BdA"
    [xfce-atomic]="XfA"
    [lxqt-atomic]="LxA"
    [base-atomic]="BsA"
    [cosmic-atomic]="CSMCA"
)'

# Define a retry function for use in recipes
retry_function := '
retry() {
    if [[ "${#}" -lt 3 ]]; then
        echo "retry usage: <number of tries> <time between retries> <command> ..."
        return 1
    fi
    tries="${1}"
    sleep="${2}"
    shift 2
    for i in $(seq 1 ${tries}); do
        if [[ ${i} -gt 1 ]]; then
            # echo "[+] Command failed. Waiting for ${sleep} seconds"
            sleep ${sleep}
        fi
        # echo "[+] Running (try: ${i}): ${@}"
        "${@}" && r=0 && break || r=$?
    done
    return $r
}
'

# Default is to only validate the manifests
all: validate

# Basic validation to make sure the manifests are not completely broken
validate:
    ./ci/validate

# Comps-sync, but without pulling latest
sync:
    #!/bin/bash
    set -euo pipefail

    if [[ ! -d fedora-comps ]]; then
        git clone https://pagure.io/fedora-comps.git
    fi

    default_variant={{default_variant}}
    version="$(rpm-ostree compose tree --print-only --repo=repo ${default_variant}.yaml | jq -r '."mutate-os-release"')"
    ./comps-sync.py --save fedora-comps/comps-f${version}.xml.in

# Sync the manifests with the content of the comps groups
comps-sync:
    #!/bin/bash
    set -euo pipefail

    if [[ ! -d fedora-comps ]]; then
        git clone https://pagure.io/fedora-comps.git
    else
        pushd fedora-comps > /dev/null || exit 1
        git fetch
        git reset --hard origin/main
        popd > /dev/null || exit 1
    fi

    default_variant={{default_variant}}
    version="$(rpm-ostree compose tree --print-only --repo=repo ${default_variant}.yaml | jq -r '."mutate-os-release"')"
    ./comps-sync.py --save fedora-comps/comps-f${version}.xml.in

# Check if the manifests are in sync with the content of the comps groups
comps-sync-check:
    #!/bin/bash
    set -euo pipefail

    if [[ ! -d fedora-comps ]]; then
        git clone https://pagure.io/fedora-comps.git
    else
        pushd fedora-comps > /dev/null || exit 1
        git fetch
        git reset --hard origin/main
        popd > /dev/null || exit 1
    fi

    default_variant={{default_variant}}
    version="$(rpm-ostree compose tree --print-only --repo=repo ${default_variant}.yaml | jq -r '."mutate-os-release"')"
    ./comps-sync.py fedora-comps/comps-f${version}.xml.in

# Output the processed manifest for a given variant (defaults to Silverblue)
manifest variant=default_variant:
    #!/bin/bash
    set -euo pipefail

    rpm-ostree compose tree --print-only --repo=repo {{variant}}.yaml

# Perform dependency resolution for a given variant (defaults to Silverblue)
compose-dry-run variant=default_variant:
    #!/bin/bash
    set -euxo pipefail

    mkdir -p repo cache logs
    if [[ ! -f "repo/config" ]]; then
        pushd repo > /dev/null || exit 1
        ostree init --repo . --mode=bare-user
        popd > /dev/null || exit 1
    fi

    rpm-ostree compose tree --unified-core --repo=repo --dry-run {{variant}}.yaml

# Alias/shortcut for compose-image command
compose variant=default_variant: (compose-image variant)

# Compose a variant using the legacy non container path (defaults to Silverblue)
compose-legacy variant=default_variant:
    #!/bin/bash
    set -euxo pipefail

    declare -A pretty_names={{pretty_names}}
    variant={{variant}}
    variant_pretty=${pretty_names[$variant]-}
    if [[ -z $variant_pretty ]]; then
        echo "Unknown variant"
        exit 1
    fi

    ./ci/validate > /dev/null || (echo "Failed manifest validation" && exit 1)

    mkdir -p repo cache logs
    if [[ ! -f "repo/config" ]]; then
        pushd repo > /dev/null || exit 1
        ostree init --repo . --mode=bare-user
        popd > /dev/null || exit 1
    fi
    # Set option to reduce fsync for transient builds
    ostree --repo=repo config set 'core.fsync' 'false'

    buildid="$(date '+%Y%m%d.0')"
    timestamp="$(date --iso-8601=sec)"
    echo "${buildid}" > .buildid

    version="$(rpm-ostree compose tree --print-only --repo=repo ${variant}.yaml | jq -r '."mutate-os-release"')"
    echo "Composing ${variant_pretty} ${version}.${buildid} ..."

    ARGS=(
        "--repo=repo"
        "--cachedir=cache"
        "--unified-core"
    )
    if [[ {{force_nocache}} == "true" ]]; then
        ARGS+=(" --force-nocache")
    fi
    CMD="rpm-ostree"
    if [[ ${EUID} -ne 0 ]]; then
        CMD="sudo rpm-ostree"
    fi

    ${CMD} compose tree "${ARGS[@]}" \
        --add-metadata-string="version=${variant_pretty} ${version}.${buildid}" \
        "${variant}-ostree.yaml" \
            |& tee "logs/${variant}_${version}_${buildid}.${timestamp}.log"

    if [[ ${EUID} -ne 0 ]]; then
        sudo chown --recursive "$(id --user --name):$(id --group --name)" repo cache
    fi

    ostree summary --repo=repo --update

# Compose an Ostree Native Container OCI image
compose-image variant=default_variant:
    #!/bin/bash
    set -euxo pipefail

    declare -A pretty_names={{pretty_names}}
    variant={{variant}}
    variant_pretty=${pretty_names[$variant]-}
    if [[ -z $variant_pretty ]]; then
        echo "Unknown variant"
        exit 1
    fi

    if [[ "${variant}" == "kinoite-nightly" ]] && [[ "$(uname -m)" != "x86_64" ]]; then
        echo "Kinoite Nightly not available for aarch64 for now"
        exit 0
    fi

    ./ci/validate > /dev/null || (echo "Failed manifest validation" && exit 1)

    mkdir -p repo cache
    if [[ ! -f "repo/config" ]]; then
        pushd repo > /dev/null || exit 1
        ostree init --repo . --mode=bare-user
        popd > /dev/null || exit 1
    fi
    # Set option to reduce fsync for transient builds
    ostree --repo=repo config set 'core.fsync' 'false'

    buildid="$(date '+%Y%m%d.0')"
    timestamp="$(date --iso-8601=sec)"
    echo "${buildid}" > .buildid

    version="$(rpm-ostree compose tree --print-only --repo=repo ${variant}.yaml | jq -r '."mutate-os-release"')"
    echo "Composing ${variant_pretty} ${version}.${buildid} ..."

    ARGS=(
        "--cachedir=cache"
        "--initialize"
        "--label=quay.expires-after=4w"
        "--max-layers=96"
    )
    if [[ {{force_nocache}} == "true" ]]; then
        ARGS+=("--force-nocache")
    fi
    # To debug with gdb, use: gdb --args ...
    CMD="rpm-ostree"
    if [[ ${EUID} -ne 0 ]]; then
        CMD="sudo rpm-ostree"
    fi

    ${CMD} compose image "${ARGS[@]}" \
        "${variant}.yaml" \
        "${variant}.ociarchive"

# Clean up everything
clean-all:
    just clean-repo
    just clean-cache

# Only clean the ostree repo
clean-repo:
    rm -rf ./repo

# Only clean the package and repo caches
clean-cache:
    rm -rf ./cache

# Build an ISO
lorax variant=default_variant:
    #!/bin/bash
    set -euxo pipefail

    rm -rf iso
    # Do not create the iso directory or lorax will fail
    mkdir -p tmp cache/lorax

    declare -A pretty_names={{pretty_names}}
    declare -A volume_id_substitutions={{volume_id_substitutions}}
    variant={{variant}}
    variant_pretty=${pretty_names[$variant]-}
    volid_sub=${volume_id_substitutions[$variant]-}
    if [[ -z $variant_pretty ]] || [[ -z $volid_sub ]]; then
        echo "Unknown variant"
        exit 1
    fi

    if [[ ! -d fedora-lorax-templates ]]; then
        git clone https://pagure.io/fedora-lorax-templates.git
    else
        pushd fedora-lorax-templates > /dev/null || exit 1
        git fetch
        git reset --hard origin/main
        popd > /dev/null || exit 1
    fi

    version_number="$(rpm-ostree compose tree --print-only --repo=repo ${variant}.yaml | jq -r '."mutate-os-release"')"
    if [[ "$(git rev-parse --abbrev-ref HEAD)" == "main" ]] || [[ -f "fedora-rawhide.repo" ]]; then
        version_pretty="Rawhide"
        version="rawhide"
    else
        version_pretty="${version_number}"
        version="${version_number}"
    fi
    source_url="https://kojipkgs.fedoraproject.org/compose/${version}/latest-Fedora-${version_pretty}/compose/Everything/x86_64/os/"
    volid="Fedora-${volid_sub}-x86_64-${version_pretty}"

    buildid=""
    if [[ -f ".buildid" ]]; then
        buildid="$(< .buildid)"
    else
        buildid="$(date '+%Y%m%d.0')"
        echo "${buildid}" > .buildid
    fi

    # Stick to the latest stable runtime available here
    # Only include a subset of Flatpaks here
    # Exhaustive list in https://pagure.io/pungi-fedora/blob/main/f/fedora.conf
    # flatpak_remote_refs="runtime/org.fedoraproject.Platform/x86_64/f39"
    # flatpak_apps=(
    #     "app/org.gnome.Calculator/x86_64/stable"
    #     "app/org.gnome.Calendar/x86_64/stable"
    #     "app/org.gnome.Extensions/x86_64/stable"
    #     "app/org.gnome.TextEditor/x86_64/stable"
    #     "app/org.gnome.clocks/x86_64/stable"
    #     "app/org.gnome.eog/x86_64/stable"
    # )
    # for ref in ${flatpak_refs[@]}; do
    #     flatpak_remote_refs+=" ${ref}"
    # done
    # FLATPAK_ARGS=""
    # FLATPAK_ARGS+=" --add-template=${pwd}/fedora-lorax-templates/ostree-based-installer/lorax-embed-flatpaks.tmpl"
    # FLATPAK_ARGS+=" --add-template-var=flatpak_remote_name=fedora"
    # FLATPAK_ARGS+=" --add-template-var=flatpak_remote_url=oci+https://registry.fedoraproject.org"
    # FLATPAK_ARGS+=" --add-template-var=flatpak_remote_refs=${flatpak_remote_refs}"

    pwd="$(pwd)"

    lorax \
        --product=Fedora \
        --version=${version_pretty} \
        --release=${buildid} \
        --source="${source_url}" \
        --variant="${variant_pretty}" \
        --nomacboot \
        --isfinal \
        --buildarch=x86_64 \
        --volid="${volid}" \
        --logfile=${pwd}/logs/lorax.log \
        --tmp=${pwd}/tmp \
        --cachedir=cache/lorax \
        --rootfs-size=8 \
        --add-template=${pwd}/fedora-lorax-templates/ostree-based-installer/lorax-configure-repo.tmpl \
        --add-template=${pwd}/fedora-lorax-templates/ostree-based-installer/lorax-embed-repo.tmpl \
        --add-template-var=ostree_install_repo=file://${pwd}/repo \
        --add-template-var=ostree_update_repo=file://${pwd}/repo \
        --add-template-var=ostree_osname=fedora \
        --add-template-var=ostree_oskey=fedora-${version_number}-primary \
        --add-template-var=ostree_contenturl=mirrorlist=https://ostree.fedoraproject.org/mirrorlist \
        --add-template-var=ostree_install_ref=fedora/${version}/x86_64/${variant} \
        --add-template-var=ostree_update_ref=fedora/${version}/x86_64/${variant} \
        ${pwd}/iso/linux

# Upload a container to a registry and sign it. Used in CI
upload-container variant=default_variant arch=default_arch:
    #!/bin/bash
    set -euxo pipefail

    {{retry_function}}

    variant={{variant}}
    arch={{arch}}

    declare -A pretty_names={{pretty_names}}
    variant_pretty=${pretty_names[$variant]-}
    if [[ -z $variant_pretty ]]; then
        echo "Unknown variant"
        exit 1
    fi

    if [[ "${variant}" == "kinoite-nightly" ]] && [[ "$(uname -m)" != "x86_64" ]]; then
        echo "Kinoite Nightly not available for aarch64 for now"
        exit 0
    fi

    if [[ "${CI}" != "true" ]]; then
        echo "Skipping: Not in CI"
        exit 1
    fi
    if [[ -z ${REGISTRY+x} ]] || [[ -z ${RELEASE_REPO+x} ]]; then
        echo "Skipping: No REGISTRY or RELEASE_REPO set"
        exit 1
    fi
    if [[ -z ${CI_REGISTRY_USER+x} ]] || [[ -z ${CI_REGISTRY_PASSWORD+x} ]]; then
        echo "Skipping: No CI_REGISTRY_USER or CI_REGISTRY_PASSWORD set"
        exit 1
    fi

    buildid=""
    if [[ -f ".buildid" ]]; then
        buildid="$(< .buildid)"
    else
        echo "Skipping: No '.buildid' file"
        exit 1
    fi

    version=""
    if [[ "$(git rev-parse --abbrev-ref HEAD)" == "main" ]] || [[ -f "fedora-rawhide.repo" ]]; then
        version="rawhide"
    else
        version="$(rpm-ostree compose tree --print-only --repo=repo ${variant}.yaml | jq -r '."mutate-os-release"')"
    fi

    # Login to the registry
    retry 5 60 skopeo login --username "${CI_REGISTRY_USER}" --password "${CI_REGISTRY_PASSWORD}" "${REGISTRY}"

    # Login to the registry again for cosign
    retry 5 60 skopeo login --username "${CI_REGISTRY_USER}" --password "${CI_REGISTRY_PASSWORD}" \
        --authfile="${HOME}/.docker/config.json" "${REGISTRY}"

    image="${REGISTRY}/${RELEASE_REPO}/${variant}"

    # Only append arch suffix if requested
    suffix=""
    if [[ ${arch} != "default" ]]; then
        suffix="-${arch}"
    fi

    SKOPEO_ARGS=(
        "--retry-times" "3"
    )

    # Support for the zstd:chunked format is not ready yet
    SKOPEO_ARGS+=("--dest-compress-format")
    if [[ ${version} == "rawhide" ]] || [[ ${version} == "43" ]]; then
        SKOPEO_ARGS+=("zstd")
    else
        SKOPEO_ARGS+=("gzip")
    fi

    # Push fully versioned tag (major version, build date/id, arch)
    retry 5 60 skopeo copy "${SKOPEO_ARGS[@]}" \
        "oci-archive:${variant}.ociarchive" \
        "docker://${image}:${version}.${buildid}${suffix}"

    # Decode private key
    printenv "COSIGN_PRIVATE_KEY" > private.key.b64
    base64 --decode private.key.b64 > private.key

    # Sign images recursively
    retry 5 60 cosign sign -y --key private.key ${image}:${version}.${buildid}${suffix}

    # Cleanup private key
    rm private.key.b64 private.key

# Create a multi-arch manifest for a given variant, push it to a registry and sign it
multi-arch-manifest variant=default_variant:
    #!/bin/bash
    set -euxo pipefail

    {{retry_function}}

    variant={{variant}}

    declare -A pretty_names={{pretty_names}}
    variant_pretty=${pretty_names[$variant]-}
    if [[ -z $variant_pretty ]]; then
        echo "Unknown variant"
        exit 1
    fi

    if [[ "${CI}" != "true" ]]; then
        echo "Skipping: Not in CI"
        exit 1
    fi
    if [[ -z ${REGISTRY+x} ]] || [[ -z ${RELEASE_REPO+x} ]]; then
        echo "Skipping: No REGISTRY or RELEASE_REPO set"
        exit 1
    fi
    if [[ -z ${CI_REGISTRY_USER+x} ]] || [[ -z ${CI_REGISTRY_PASSWORD+x} ]]; then
        echo "Skipping: No CI_REGISTRY_USER or CI_REGISTRY_PASSWORD set"
        exit 1
    fi

    buildid=""
    if [[ -f ".buildid" ]]; then
        buildid="$(< .buildid)"
    else
        echo "Skipping: No '.buildid' file"
        exit 1
    fi

    version=""
    if [[ "$(git rev-parse --abbrev-ref HEAD)" == "main" ]] || [[ -f "fedora-rawhide.repo" ]]; then
        version="rawhide"
    else
        version="$(rpm-ostree compose tree --print-only --repo=repo ${variant}.yaml | jq -r '."mutate-os-release"')"
    fi

    # Login to the registry
    retry 5 60 skopeo login --username "${CI_REGISTRY_USER}" --password "${CI_REGISTRY_PASSWORD}" "${REGISTRY}"

    # Login to the registry again for cosign
    retry 5 60 skopeo login --username "${CI_REGISTRY_USER}" --password "${CI_REGISTRY_PASSWORD}" \
        --authfile="${HOME}/.docker/config.json" "${REGISTRY}"

    image="${REGISTRY}/${RELEASE_REPO}/${variant}"

    # Create manifest with full version tags
    if [[ "${variant}" != "kinoite-nightly" ]]; then
        buildah manifest create "${image}:${version}.${buildid}" \
                "${image}:${version}.${buildid}-x86_64" \
                "${image}:${version}.${buildid}-aarch64"
    else
        echo "Kinoite Nightly not available for aarch64 for now"
        buildah manifest create "${image}:${version}.${buildid}" \
                "${image}:${version}.${buildid}-x86_64"
    fi

    # Decode private key
    printenv "COSIGN_PRIVATE_KEY" > private.key.b64
    base64 --decode private.key.b64 > private.key

    # Push fully versioned dual arch manifest tag (major version, build date/id)
    retry 5 60 buildah manifest push \
        "${image}:${version}.${buildid}" \
        "docker://${image}:${version}.${buildid}"

    # Sign manifest
    retry 5 60 cosign sign -y --key private.key ${image}:${version}.${buildid}

    # Update "un-versioned" tag (only major version)
    retry 5 60 buildah manifest push \
        "${image}:${version}.${buildid}" \
        "docker://${image}:${version}"

    # Sign manifest
    retry 5 60 cosign sign -y --key private.key ${image}:${version}

    # Cleanup private key
    rm private.key.b64 private.key
