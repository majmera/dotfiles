#!/usr/bin/env bash
set -euo pipefail

usage() {
    cat <<'EOF'
Usage: hydrate_compile_command_inputs.sh [--flavor DEBUG|RETAIL] [--repo datapath|cyc_core|both] [--print-targets] [--workspace-root PATH]

Hydrates the minimal cached target outputs needed to generate compile_commands for
datapath (DP2) and/or cyc_core without running a full build.
EOF
}

die() {
    echo "ERROR: $*" >&2
    exit 1
}

resolve_workspace_root() {
    local candidate=""

    if [[ -n "${WORKSPACE_ROOT_OVERRIDE}" ]]; then
        candidate=$(readlink -f "${WORKSPACE_ROOT_OVERRIDE}")
    elif git -C "${PWD}" rev-parse --show-toplevel >/dev/null 2>&1; then
        candidate=$(git -C "${PWD}" rev-parse --show-toplevel)
    elif [[ -f "${PWD}/Makefile" && -d "${PWD}/source" && -d "${PWD}/utils" ]]; then
        candidate=$(readlink -f "${PWD}")
    elif [[ -f "${SCRIPT_DIR}/../Makefile" && -d "${SCRIPT_DIR}/../source" && -d "${SCRIPT_DIR}/../utils" ]]; then
        candidate=$(readlink -f "${SCRIPT_DIR}/..")
    else
        die "unable to resolve cyclone workspace root; run from the workspace root or pass --workspace-root PATH"
    fi

    [[ -f "${candidate}/Makefile" && -d "${candidate}/source/cyc_core" && -d "${candidate}/utils" ]] || \
        die "resolved workspace root is not a cyclone checkout: ${candidate}"
    echo "${candidate}"
}

prepare_local_datapath() {
    local top="${ROOTDIR}/source/datapath"
    local outdir="${ROOTDIR}/output_${FLAVOR}/datapath"
    local outfile="${outdir}/datapath.tar.gz"
    local version_file="${top}/version.txt"

    [[ -d "${top}" ]] || die "missing datapath source tree: ${top}"
    mkdir -p "${outdir}"
    git -C "${top}" rev-parse HEAD > "${version_file}"

    mapfile -t input_files < <(git -C "${top}" ls-files .dockerignore Dockerfile cyclone)
    input_files+=("version.txt")
    tar -C "${top}" -czf "${outfile}" "${input_files[@]}"
    rm -f "${version_file}"
    echo "Prepared local datapath package: ${outfile}"
}

restore_builder_marker_from_cache() {
    local output_dir="${ROOTDIR}/output_${FLAVOR}"
    local final_path="${output_dir}/docker-images/sles15sp6-sles_builder/sles15sp6-sles_builder.docker"

    [[ -f "${final_path}" ]] && return 0

    local pattern="${output_dir}/artifactory/make-builds/make-cache/docker-images"/*/sles15sp6-sles_builder/sles15sp6-sles_builder.docker
    local candidate
    candidate=$(ls -1t ${pattern} 2>/dev/null | head -n 1 || true)
    [[ -n "${candidate}" ]] || return 0

    mkdir -p "$(dirname "${final_path}")"
    cp -f "${candidate}" "${final_path}"
    echo "Restored builder marker from cache: ${final_path}"
}

materialize_cached_docker_images() {
    local output_dir="${ROOTDIR}/output_${FLAVOR}"
    local final_path="${output_dir}/docker-images/sles15sp6-sles_builder/sles15sp6-sles_builder.docker"
    local status=0

    [[ -f "${final_path}" ]] && return 0

    make \
        -C "${ROOTDIR}" \
        "flavor=${FLAVOR}" \
        "acache=yes" \
        "mcache=yes" \
        "statistics=no" \
        "otel_cli_enable=no" \
        "outputs_check=no" \
        docker-images || status=$?

    if [[ -f "${final_path}" ]]; then
        [[ ${status} -ne 0 ]] && echo "Ignoring non-zero make exit (${status}) because docker-images outputs were materialized."
        return 0
    fi

    return ${status}
}

REPO_MODE=both
FLAVOR=DEBUG
PRINT_TARGETS=no
WORKSPACE_ROOT_OVERRIDE=

while [[ $# -gt 0 ]]; do
    case "$1" in
        --flavor)
            [[ $# -ge 2 ]] || die "--flavor requires a value"
            FLAVOR=${2^^}
            shift 2
            ;;
        --repo)
            [[ $# -ge 2 ]] || die "--repo requires a value"
            REPO_MODE=$2
            shift 2
            ;;
        --print-targets)
            PRINT_TARGETS=yes
            shift
            ;;
        --workspace-root|--root)
            [[ $# -ge 2 ]] || die "$1 requires a value"
            WORKSPACE_ROOT_OVERRIDE=$2
            shift 2
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            die "unknown argument: $1"
            ;;
    esac
done

[[ "${FLAVOR}" == "DEBUG" || "${FLAVOR}" == "RETAIL" ]] || die "unsupported flavor: ${FLAVOR}"
[[ "${REPO_MODE}" == "datapath" || "${REPO_MODE}" == "cyc_core" || "${REPO_MODE}" == "both" ]] || die "unsupported repo mode: ${REPO_MODE}"

SCRIPT_PATH=$(readlink -f "$0")
SCRIPT_DIR=$(dirname "${SCRIPT_PATH}")
ROOTDIR=$(resolve_workspace_root)

declare -a targets=()
case "${REPO_MODE}" in
    datapath)
        targets=(
            layered-services
            cdre-ng
            cyc_crypto
            cyc_dp_protobuf
            datapath
            docker-images
            event-generator
            feature-framework
            third_party
        )
        ;;
    cyc_core)
        targets=(
            cyc_crypto
            cyc_dp_protobuf
            cyc_net_protobuf
            docker-images
            event-generator
            nt-nvmeof-frontend
            xblock
            feature-framework
            third_party
        )
        ;;
    both)
        targets=(
            layered-services
            cdre-ng
            cyc_crypto
            cyc_dp_protobuf
            cyc_net_protobuf
            datapath
            docker-images
            event-generator
            nt-nvmeof-frontend
            xblock
            feature-framework
            third_party
        )
        ;;
esac

declare -a make_targets=()
for target in "${targets[@]}"; do
    make_targets+=("cache_target_pull_${target}")
done

printf 'Hydration targets (%s, flavor=%s):\n' "${REPO_MODE}" "${FLAVOR}"
printf '  %s\n' "${make_targets[@]}"

if [[ "${PRINT_TARGETS}" == "yes" ]]; then
    exit 0
fi

status=0
make \
    -C "${ROOTDIR}" \
    "flavor=${FLAVOR}" \
    "acache=yes" \
    "mcache=yes" \
    "statistics=no" \
    "otel_cli_enable=no" \
    "outputs_check=no" \
    "${make_targets[@]}" || status=$?

OUTPUT_DIR="${ROOTDIR}/output_${FLAVOR}"
if [[ "${REPO_MODE}" == "datapath" || "${REPO_MODE}" == "both" ]]; then
    prepare_local_datapath
fi
restore_builder_marker_from_cache
if [[ ! -f "${OUTPUT_DIR}/docker-images/sles15sp6-sles_builder/sles15sp6-sles_builder.docker" ]] && [[ " ${targets[*]} " == *" docker-images "* ]]; then
    materialize_cached_docker_images || true
    restore_builder_marker_from_cache
fi

declare -a missing=()
if [[ " ${targets[*]} " == *" datapath "* ]] && [[ ! -f "${OUTPUT_DIR}/datapath/datapath.tar.gz" ]]; then
    missing+=("datapath")
fi
if [[ " ${targets[*]} " == *" docker-images "* ]] && [[ ! -f "${OUTPUT_DIR}/docker-images/sles15sp6-sles_builder/sles15sp6-sles_builder.docker" ]]; then
    missing+=("docker-images")
fi

if [[ ${#missing[@]} -eq 0 ]]; then
    [[ ${status} -ne 0 ]] && echo "Ignoring non-zero make exit (${status}) because all requested cache targets were hydrated."
    exit 0
fi

die "failed to hydrate required targets: ${missing[*]}"
