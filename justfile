# This is a justfile. See https://github.com/casey/just
# This is only used for local development. The builds made on the Fedora
# infrastructure are run via Pungi in a Koji runroot.

# Set a default for some recipes
default_variant := "xfce-atomic"
default_arch := "default"
# Current default in Pungi
force_nocache := "true"

# Just doesn't have a native dict type, but quoted bash dictionary works fine
pretty_names := '(
    [xfce-atomic]="XFCE Atomic"
)'

# subset of the map from https://pagure.io/pungi-fedora/blob/main/f/general.conf
volume_id_substitutions := '(
    [xfce-atomic]="XfA"
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

# Output the processed manifest for a given variant (defaults to xfce-atomic)
manifest variant=default_variant:
    #!/bin/bash
    set -euo pipefail

    rpm-ostree compose tree --print-only --repo=repo {{variant}}.yaml

# Perform dependency resolution for a given variant (defaults to xfce-atomic)
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

# Compose a variant using the legacy non container path (defaults to xfce-atomic)
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

