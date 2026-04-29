#!/usr/bin/env bash
set -euo pipefail

usage() {
    cat <<'EOF'
Usage: generate_compile_commands.sh [--flavor DEBUG|RETAIL] [--repo datapath|cyc_core|both] [--hydrate] [--workspace-root PATH]

Generates compile_commands for the datapath (DP2) and/or cyc_core platform trees
without running a full build. This reuses the existing output_<flavor> artifacts
and configures the same CMake/Ninja build directories that the normal build uses,
but it skips ninja/make compilation.
EOF
}

die() {
    echo "ERROR: $*" >&2
    exit 1
}

require_tool() {
    command -v "$1" >/dev/null 2>&1 || die "missing required tool: $1"
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

resolve_hydrate_script() {
    local candidate="${SCRIPT_DIR}/hydrate_compile_command_inputs.sh"
    [[ -f "${candidate}" ]] && { echo "${candidate}"; return 0; }

    candidate="${PDRTOP}/utils/hydrate_compile_command_inputs.sh"
    [[ -f "${candidate}" ]] && { echo "${candidate}"; return 0; }

    die "unable to locate hydrate_compile_command_inputs.sh next to ${SCRIPT_PATH} or under ${PDRTOP}/utils"
}

maybe_hydrate_inputs() {
    [[ "${INSIDE_BUILDER}" == "yes" ]] && return 0

    local hydrate_needed=no
    local reasons=()
    local key missing_count=0 first_missing=""

    if [[ "${HYDRATE}" == "yes" ]]; then
        hydrate_needed=yes
        reasons+=("requested via --hydrate")
    fi

    for key in "${!bpdr_inputs[@]}"; do
        if [[ ! -e "${bpdr_inputs[$key]}" ]]; then
            missing_count=$((missing_count + 1))
            [[ -z "${first_missing}" ]] && first_missing="${key} -> ${bpdr_inputs[$key]}"
        fi
    done
    if [[ ${missing_count} -gt 0 ]]; then
        hydrate_needed=yes
        reasons+=("missing ${missing_count} required inputs (for example ${first_missing})")
    fi

    if { ! command -v cmake >/dev/null 2>&1 || ! command -v ninja >/dev/null 2>&1; } && [[ ! -f "${BUILDER_IMAGE_FILE}" ]]; then
        hydrate_needed=yes
        reasons+=("missing builder image reference ${BUILDER_IMAGE_FILE}")
    fi

    if [[ "${hydrate_needed}" == "yes" ]]; then
        printf 'Hydrating compile-command inputs because: %s\n' "$(IFS='; '; echo "${reasons[*]}")"
        "${HYDRATE_SCRIPT}" --flavor "${FLAVOR}" --repo "${REPO_MODE}" --workspace-root "${PDRTOP}"
    fi
}

restore_missing_inputs_from_cache() {
    local cache_root="${OUTPUT_ROOT}/artifactory/make-builds/make-cache"

    local key file rel suffix candidate
    for key in "${!bpdr_inputs[@]}"; do
        file="${bpdr_inputs[$key]}"
        [[ -e "${file}" ]] && continue
        [[ "${file}" == "${OUTPUT_ROOT}/"* ]] || continue

        if [[ -e "${file}.cache_pull.link2artifact" ]]; then
            mkdir -p "$(dirname "${file}")"
            cp -f "${file}.cache_pull.link2artifact" "${file}"
            echo "Restored input ${key} from cache link: ${file}"
            continue
        fi

        [[ -d "${cache_root}" ]] || continue
        rel="${file#${OUTPUT_ROOT}/}"
        suffix="${rel#*/}"
        candidate=$(
            {
                find "${cache_root}" -path "*/${rel}" -type f -printf '%T@ %p\n' 2>/dev/null
                [[ "${suffix}" != "${rel}" ]] && find "${cache_root}" -path "*/${suffix}" -type f -printf '%T@ %p\n' 2>/dev/null
            } | sort -nr | head -n 1 | cut -d' ' -f2- || true
        )
        [[ -n "${candidate}" ]] || continue

        mkdir -p "$(dirname "${file}")"
        cp -f "${candidate}" "${file}"
        echo "Restored input ${key} from cache: ${file}"
    done
}

materialize_missing_inputs_from_cache() {
    [[ "${INSIDE_BUILDER}" == "yes" ]] && return 0

    declare -A target_by_input=(
        [layered-services]=layered-services
        [cdre-ng]=cdre-ng
        [cyc_crypto]=cyc_crypto
        [cyc_crypto_lockbox]=cyc_crypto
        [cyc_crypto_util]=cyc_crypto
        [protobuf-common-v3]=cyc_dp_protobuf
        [protobuf-dp-v3]=cyc_dp_protobuf
        [protobuf-platform-v3]=cyc_dp_protobuf
        [cyc_net_protobuf_go]=cyc_net_protobuf
        [cyc_net_protobuf_python]=cyc_net_protobuf
        [sles15sp6-sles_builder]=docker-images
        [event-sources]=event-generator
        [c-feature-state-client]=feature-framework
        [cpp-feature-state-client]=feature-framework
        [feature-state-generation-utils]=feature-framework
        [nt-nvmeof-frontend]=nt-nvmeof-frontend
        [xblock-src]=xblock
        [fio_files]=third_party
        [spdk_files]=third_party
        [libck_files]=third_party
        [scst_files]=third_party
        [scst_extra_files]=third_party
        [Intel_qat_files]=third_party
        [Intel_qat20_files]=third_party
        [PNVMeT_files]=third_party
        [PMC_NVRAM_files]=third_party
        [PMC_NVRAM_extra_files]=third_party
        [pmapper_files]=third_party
        [nvme_common_files]=third_party
        [nvme_common_extra_files]=third_party
        [switchtec_files]=third_party
        [ipreflect_files]=third_party
    )
    declare -A needed_targets=()
    local key target status=0

    for key in "${!bpdr_inputs[@]}"; do
        [[ -e "${bpdr_inputs[$key]}" ]] && continue
        target="${target_by_input[$key]:-}"
        [[ -n "${target}" ]] || continue
        needed_targets["${target}"]=yes
    done

    [[ ${#needed_targets[@]} -gt 0 ]] || return 0

    local targets=("${!needed_targets[@]}")
    echo "Materializing cached target outputs for missing inputs: ${targets[*]}"
    make \
        -C "${PDRTOP}" \
        "flavor=${FLAVOR}" \
        "acache=yes" \
        "mcache=yes" \
        "statistics=no" \
        "otel_cli_enable=no" \
        "outputs_check=no" \
        "${targets[@]}" || status=$?

    if [[ ${status} -ne 0 ]]; then
        echo "Ignoring non-zero make exit (${status}) while materializing cached target outputs; re-checking required inputs."
    fi
}

ensure_local_tooling_or_reexec() {
    if command -v cmake >/dev/null 2>&1 && command -v ninja >/dev/null 2>&1; then
        return 0
    fi

    [[ "${INSIDE_BUILDER}" == "yes" ]] && die "builder container is missing cmake and/or ninja"

    require_tool docker
    [[ -f "${BUILDER_IMAGE_FILE}" ]] || die "missing builder image reference: ${BUILDER_IMAGE_FILE}"

    local builder_image
    builder_image=$(<"${BUILDER_IMAGE_FILE}")
    [[ -n "${builder_image}" ]] || die "empty builder image reference in ${BUILDER_IMAGE_FILE}"

    local docker_args=(
        run --rm
        -u "$(id -u):$(id -g)"
        -v "${PDRTOP}:${PDRTOP}"
        -w "${PDRTOP}"
        -e "HOME=/tmp"
    )
    if [[ "${SCRIPT_DIR}" != "${PDRTOP}" && "${SCRIPT_DIR}" != "${PDRTOP}/"* ]]; then
        docker_args+=(-v "${SCRIPT_DIR}:${SCRIPT_DIR}:ro")
    fi
    local passthrough_vars=(DEVOPS_GITHUB_TOKEN DEVOPS_GITHUB_SERVER DEVOPS_ARTIFACTORY_SERVER)
    local var
    for var in "${passthrough_vars[@]}"; do
        [[ -n "${!var:-}" ]] && docker_args+=(-e "${var}=${!var}")
    done

    echo "Host is missing cmake/ninja; re-running inside builder docker ${builder_image}"
    exec docker "${docker_args[@]}" "${builder_image}" \
        /bin/bash -lc "$(printf '%q ' "${SCRIPT_PATH}" --flavor "${FLAVOR}" --repo "${REPO_MODE}" --inside-builder --workspace-root "${PDRTOP}")"
}

link_input() {
    local key=$1
    local file=$2
    local link="${INPUT_ARTIFACT_CACHE}/link/${key}"

    [[ "${key}" == "coreos-linux-headers-gcached" ]] && link="${INPUT_ARTIFACT_CACHE}/link/coreos-linux-headers"
    [[ "${key}" == "coreos-version-text" ]] && link="${INPUT_ARTIFACT_CACHE}/link/coreos-version"
    [[ "${key}" == "ddsd_${FLAVOR_LC}" ]] && link="${INPUT_ARTIFACT_CACHE}/link/ddsd"
    [[ "${key}" == "trident-os-version-text" ]] && link="${INPUT_ARTIFACT_CACHE}/link/trident-os-version"
    if [[ "${key}" != "centos7-builder" && "${key}" != "analytics-engine" && "${file}" == *.docker ]]; then
        link="${INPUT_ARTIFACT_CACHE}/link/${key#*-}"
    fi

    [[ -n "${file}" ]] || return 0
    [[ -e "${file}" ]] || die "input artifact for ${key} not found: ${file}"
    ln -sfn "${file}" "${link}"
    if [[ "${key}" == *"sles_builder" ]]; then
        ln -sfn "${file}" "${INPUT_ARTIFACT_CACHE}/link/builder"
    fi
}

populate_inputs() {
    declare -gA bpdr_inputs=()
    local output_entries=()
    local binary_entries=()

    case "${REPO_MODE}" in
        datapath)
            output_entries=(
                "layered-services=layered-services/layered-services.tar.gz"
                "cdre-ng=cdre-ng/cdre-ng/cdre-ng.tgz"
                "cyc_crypto=cyc_crypto/cyc_crypto/cyc_crypto.tar.gz"
                "cyc_crypto_lockbox=cyc_crypto/cyc_crypto_lockbox/cyc_crypto_lockbox.tar.gz"
                "protobuf-common-v3=cyc_dp_protobuf/protobuf-common-v3/cyc_common_protobuf_3.tar.gz"
                "protobuf-dp-v3=cyc_dp_protobuf/protobuf-dp-v3/cyc_dp_protobuf_3.tar.gz"
                "protobuf-platform-v3=cyc_dp_protobuf/protobuf-platform-v3/cyc_platform_protobuf_3.tar.gz"
                "datapath=datapath/datapath.tar.gz"
                "sles15sp6-sles_builder=docker-images/sles15sp6-sles_builder/sles15sp6-sles_builder.docker"
                "event-sources=event-generator/event-sources/event-sources-1.0-SNAPSHOT.tar.gz"
                "c-feature-state-client=feature-framework/c-feature-state-client/feature-framework-c_client-1.0-SNAPSHOT.tgz"
                "cpp-feature-state-client=feature-framework/cpp-feature-state-client/feature-framework-cpp_client-1.0-SNAPSHOT.tgz"
                "feature-state-generation-utils=feature-framework/feature-state-generation-utils/feature-framework-state_generation_utils-1.0-SNAPSHOT.tgz"
                "fio_files=third_party/fio_files/fio_files.tgz"
                "spdk_files=third_party/spdk_files/spdk_files.tgz"
                "libck_files=third_party/libck_files/libck_files.tgz"
            )
            binary_entries=(
                "MsgSvc=MsgSvc/MsgSvc-0.1.29.tar.gz"
                "cedrs=cedrs/cedrs-2.49.49-CentOS7-X86_64.tar.gz"
                "cppzmq=cppzmq/cppzmq-43.tar.gz"
                "ddsd_debug=ddsd_debug/ddsd_1.0.33.0-debug_linux_x86_64.tar.gz"
                "ddsd_retail=ddsd_retail/ddsd_1.0.33.0-retail_linux_x86_64.tar.gz"
                "oclint=oclint/oclint-0.11-x86_64-linux-3.13.0-92-generic.tar.gz"
                "scsi-target-utils=scsi-target-utils/scsi-target-utils-2597b7.10.tar.gz"
                "thinfat32=thinfat32/thinfat32-0.1.4.tar.gz"
            )
            ;;
        cyc_core)
            output_entries=(
                "cyc_crypto=cyc_crypto/cyc_crypto/cyc_crypto.tar.gz"
                "cyc_crypto_lockbox=cyc_crypto/cyc_crypto_lockbox/cyc_crypto_lockbox.tar.gz"
                "cyc_crypto_util=cyc_crypto/cyc_crypto_util/cyc_crypto_util.tar.gz"
                "protobuf-platform-v3=cyc_dp_protobuf/protobuf-platform-v3/cyc_platform_protobuf_3.tar.gz"
                "sles15sp6-sles_builder=docker-images/sles15sp6-sles_builder/sles15sp6-sles_builder.docker"
                "event-sources=event-generator/event-sources/event-sources-1.0-SNAPSHOT.tar.gz"
                "cyc_net_protobuf_go=cyc_net_protobuf/cyc_net_protobuf_go/cyc_net_protobuf_go-local.tar.gz"
                "cyc_net_protobuf_python=cyc_net_protobuf/cyc_net_protobuf_python/cyc_net_protobuf_python-local.tar.gz"
                "nt-nvmeof-frontend=nt-nvmeof-frontend/nt-nvmeof-frontend/nt-nvmeof-frontend.tgz"
                "xblock-src=xblock/xblock-src/xblock.tgz"
                "c-feature-state-client=feature-framework/c-feature-state-client/feature-framework-c_client-1.0-SNAPSHOT.tgz"
                "cpp-feature-state-client=feature-framework/cpp-feature-state-client/feature-framework-cpp_client-1.0-SNAPSHOT.tgz"
                "scst_files=third_party/scst_files/scst_files.tgz"
                "scst_extra_files=third_party/scst_extra_files/scst_extra_files.tgz"
                "Intel_qat_files=third_party/Intel_qat_files/Intel_qat_files.tgz"
                "Intel_qat20_files=third_party/Intel_qat20_files/Intel_qat20_files.tgz"
                "PNVMeT_files=third_party/PNVMeT_files/PNVMeT_files.tgz"
                "PMC_NVRAM_files=third_party/PMC_NVRAM_files/PMC_NVRAM_files.tgz"
                "PMC_NVRAM_extra_files=third_party/PMC_NVRAM_extra_files/PMC_NVRAM_extra_files.tgz"
                "pmapper_files=third_party/pmapper_files/pmapper_files.tgz"
                "nvme_common_files=third_party/nvme_common_files/nvme_common_files.tgz"
                "nvme_common_extra_files=third_party/nvme_common_extra_files/nvme_common_extra_files.tgz"
                "libck_files=third_party/libck_files/libck_files.tgz"
                "switchtec_files=third_party/switchtec_files/switchtec_files.tgz"
                "ipreflect_files=third_party/ipreflect_files/ipreflect_files.tgz"
            )
            binary_entries=(
                "systemd_238_headers=systemd_238_headers/systemd_238_headers.tgz"
            )
            ;;
        both)
            output_entries=(
                "layered-services=layered-services/layered-services.tar.gz"
                "cdre-ng=cdre-ng/cdre-ng/cdre-ng.tgz"
                "cyc_crypto=cyc_crypto/cyc_crypto/cyc_crypto.tar.gz"
                "cyc_crypto_lockbox=cyc_crypto/cyc_crypto_lockbox/cyc_crypto_lockbox.tar.gz"
                "cyc_crypto_util=cyc_crypto/cyc_crypto_util/cyc_crypto_util.tar.gz"
                "protobuf-common-v3=cyc_dp_protobuf/protobuf-common-v3/cyc_common_protobuf_3.tar.gz"
                "protobuf-dp-v3=cyc_dp_protobuf/protobuf-dp-v3/cyc_dp_protobuf_3.tar.gz"
                "protobuf-platform-v3=cyc_dp_protobuf/protobuf-platform-v3/cyc_platform_protobuf_3.tar.gz"
                "cyc_net_protobuf_go=cyc_net_protobuf/cyc_net_protobuf_go/cyc_net_protobuf_go-local.tar.gz"
                "cyc_net_protobuf_python=cyc_net_protobuf/cyc_net_protobuf_python/cyc_net_protobuf_python-local.tar.gz"
                "datapath=datapath/datapath.tar.gz"
                "sles15sp6-sles_builder=docker-images/sles15sp6-sles_builder/sles15sp6-sles_builder.docker"
                "event-sources=event-generator/event-sources/event-sources-1.0-SNAPSHOT.tar.gz"
                "nt-nvmeof-frontend=nt-nvmeof-frontend/nt-nvmeof-frontend/nt-nvmeof-frontend.tgz"
                "xblock-src=xblock/xblock-src/xblock.tgz"
                "c-feature-state-client=feature-framework/c-feature-state-client/feature-framework-c_client-1.0-SNAPSHOT.tgz"
                "cpp-feature-state-client=feature-framework/cpp-feature-state-client/feature-framework-cpp_client-1.0-SNAPSHOT.tgz"
                "feature-state-generation-utils=feature-framework/feature-state-generation-utils/feature-framework-state_generation_utils-1.0-SNAPSHOT.tgz"
                "Intel_qat_files=third_party/Intel_qat_files/Intel_qat_files.tgz"
                "Intel_qat20_files=third_party/Intel_qat20_files/Intel_qat20_files.tgz"
                "scst_files=third_party/scst_files/scst_files.tgz"
                "scst_extra_files=third_party/scst_extra_files/scst_extra_files.tgz"
                "PNVMeT_files=third_party/PNVMeT_files/PNVMeT_files.tgz"
                "fio_files=third_party/fio_files/fio_files.tgz"
                "spdk_files=third_party/spdk_files/spdk_files.tgz"
                "PMC_NVRAM_files=third_party/PMC_NVRAM_files/PMC_NVRAM_files.tgz"
                "PMC_NVRAM_extra_files=third_party/PMC_NVRAM_extra_files/PMC_NVRAM_extra_files.tgz"
                "pmapper_files=third_party/pmapper_files/pmapper_files.tgz"
                "nvme_common_files=third_party/nvme_common_files/nvme_common_files.tgz"
                "nvme_common_extra_files=third_party/nvme_common_extra_files/nvme_common_extra_files.tgz"
                "libck_files=third_party/libck_files/libck_files.tgz"
                "switchtec_files=third_party/switchtec_files/switchtec_files.tgz"
                "ipreflect_files=third_party/ipreflect_files/ipreflect_files.tgz"
            )
            binary_entries=(
                "MsgSvc=MsgSvc/MsgSvc-0.1.29.tar.gz"
                "cedrs=cedrs/cedrs-2.49.49-CentOS7-X86_64.tar.gz"
                "cppzmq=cppzmq/cppzmq-43.tar.gz"
                "ddsd_debug=ddsd_debug/ddsd_1.0.33.0-debug_linux_x86_64.tar.gz"
                "ddsd_retail=ddsd_retail/ddsd_1.0.33.0-retail_linux_x86_64.tar.gz"
                "oclint=oclint/oclint-0.11-x86_64-linux-3.13.0-92-generic.tar.gz"
                "scsi-target-utils=scsi-target-utils/scsi-target-utils-2597b7.10.tar.gz"
                "systemd_238_headers=systemd_238_headers/systemd_238_headers.tgz"
                "thinfat32=thinfat32/thinfat32-0.1.4.tar.gz"
            )
            ;;
    esac
    local entry key rel

    for entry in "${output_entries[@]}"; do
        key=${entry%%=*}
        rel=${entry#*=}
        bpdr_inputs["${key}"]="${OUTPUT_ROOT}/${rel}"
    done
    for entry in "${binary_entries[@]}"; do
        key=${entry%%=*}
        rel=${entry#*=}
        bpdr_inputs["${key}"]="${TOP}/binaries/key_val/${rel}"
    done
    bpdr_inputs["feature_flags_default"]="${PDRTOP}/configs/feature_flags_default.json"
}

prepare_dmcache() {
    rm -rf "${INPUT_ARTIFACT_CACHE}/link"
    mkdir -p "${INPUT_ARTIFACT_CACHE}/link"

    local key
    for key in "${!bpdr_inputs[@]}"; do
        link_input "${key}" "${bpdr_inputs[$key]}"
    done
}

cyc_extract_obj() {
    local root=$1
    local extract_dir=$2
    local obj=$3

    if [[ "${root}/.${obj}_marker" -nt "${INPUT_ARTIFACT_CACHE}/link/${obj}" ]]; then
        return 0
    fi

    tar -I pigz --exclude ".git*" --touch -C "${extract_dir}" -xf "${INPUT_ARTIFACT_CACHE}/link/${obj}"
    touch "${root}/.${obj}_marker"
}

cyc_extract_third_party() {
    local extract_type=$1
    local extract_dir obj
    local extraction_list=()
    local extraction_list_add_top_folder=()

    case "${extract_type}" in
        plt)
            extract_dir="${TOP}/cyc_platform/${OBJ_DIR}"
            extraction_list=(scst_files scst_extra_files Intel_qat_files Intel_qat20_files PNVMeT_files PMC_NVRAM_files PMC_NVRAM_extra_files pmapper_files nvme_common_files nvme_common_extra_files libck_files switchtec_files systemd_238_headers ipreflect_files)
            extraction_list_add_top_folder=(cyc_crypto cyc_crypto_lockbox cyc_net_protobuf_go cyc_net_protobuf_python c-feature-state-client cpp-feature-state-client nt-nvmeof-frontend xblock-src)
            ;;
        datapath)
            extract_dir="${TOP}/datapath/artifacts"
            extraction_list=(fio_files libck_files spdk_files)
            extraction_list_add_top_folder=(cyc_crypto cyc_crypto_lockbox)
            ;;
        *)
            die "unsupported third-party extraction type: ${extract_type}"
            ;;
    esac

    mkdir -p "${extract_dir}"
    for obj in "${extraction_list[@]}"; do
        cyc_extract_obj "${extract_dir}" "${extract_dir}" "${obj}"
    done
    for obj in "${extraction_list_add_top_folder[@]}"; do
        mkdir -p "${extract_dir}/${obj}"
        cyc_extract_obj "${extract_dir}" "${extract_dir}/${obj}" "${obj}"
    done
}

prepare_datapath_tree() {
    export CYC_BUILD_CYC_APP_DIRECTORY="${TOP}/datapath"
    if [[ "${CYC_BUILD_CYC_APP_DIRECTORY}/datapath_marker" -nt "${INPUT_ARTIFACT_CACHE}/link/datapath" ]]; then
        :
    else
        mkdir -p "${CYC_BUILD_CYC_APP_DIRECTORY}"
        tar -I pigz -C "${CYC_BUILD_CYC_APP_DIRECTORY}" -xf "${INPUT_ARTIFACT_CACHE}/link/datapath"
        touch "${CYC_BUILD_CYC_APP_DIRECTORY}/datapath_marker"
    fi

    export CYC_BUILD_CYC_APP_CYCLONE_DIRECTORY="${CYC_BUILD_CYC_APP_DIRECTORY}/cyclone"
    export CYC_BUILD_OUTPUT_DIRECTORY="${CYC_BUILD_CYC_APP_DIRECTORY}/${DM_BINARY_DIR}/simulation"
    export CYC_BUILD_TARGET_DIRECTORY="${CYC_BUILD_OUTPUT_DIRECTORY}"
    export CYC_BUILD_SCRIPT_DIRECTORY="${CYC_BUILD_CYC_APP_CYCLONE_DIRECTORY}/tools/build"
    export CYC_BUILD_ARTIFACTS_DIRECTORY="${CYC_BUILD_CYC_APP_DIRECTORY}/artifacts"
    export CYC_BUILD_TARGET=simulation

    mkdir -p "${CYC_BUILD_OUTPUT_DIRECTORY}" "${CYC_BUILD_TARGET_DIRECTORY}" "${CYC_BUILD_ARTIFACTS_DIRECTORY}"

    local trace_persistent="${CYC_BUILD_CYC_APP_DIRECTORY}/trace_persistent.db"
    local trace_persistent_phys="${CYC_BUILD_CYC_APP_DIRECTORY}/trace_persistent.db.${DEVOPS_BUILD_FLAVOR}"
    local trace_volatile="${CYC_BUILD_CYC_APP_DIRECTORY}/trace_volatile.db"
    local trace_volatile_phys="${CYC_BUILD_CYC_APP_DIRECTORY}/trace_volatile.db.${DEVOPS_BUILD_FLAVOR}"
    local new_traces_db="${CYC_BUILD_CYC_APP_DIRECTORY}/trace_db.db"
    local new_traces_db_phys="${CYC_BUILD_CYC_APP_DIRECTORY}/trace_db.db.${DEVOPS_BUILD_FLAVOR}"

    ln -snf "$(basename "${trace_persistent_phys}")" "${trace_persistent}"
    ln -snf "$(basename "${trace_volatile_phys}")" "${trace_volatile}"
    ln -snf "$(basename "${new_traces_db_phys}")" "${new_traces_db}"

    local artifacts_list=(cedrs cppzmq event-sources MsgSvc oclint protobuf-dp-v3 scsi-target-utils thinfat32 c-feature-state-client cpp-feature-state-client feature-state-generation-utils ddsd protobuf-platform-v3 protobuf-common-v3)
    local obj
    for obj in "${artifacts_list[@]}"; do
        if [[ "${CYC_BUILD_ARTIFACTS_DIRECTORY}/${obj}" -nt "${INPUT_ARTIFACT_CACHE}/link/${obj}" ]]; then
            continue
        fi
        rm -rf "${CYC_BUILD_ARTIFACTS_DIRECTORY:?}/${obj}"
        mkdir -p "${CYC_BUILD_ARTIFACTS_DIRECTORY}/${obj}"
        tar -C "${CYC_BUILD_ARTIFACTS_DIRECTORY}/${obj}" -zx --touch --exclude ".git*" -f "${INPUT_ARTIFACT_CACHE}/link/${obj}"
    done

    local layered_services_dest="${CYC_BUILD_CYC_APP_DIRECTORY}/cyclone/LayeredService"
    if [[ "${layered_services_dest}/LayeredService_marker" -nt "${INPUT_ARTIFACT_CACHE}/link/layered-services" ]]; then
        :
    else
        mkdir -p "${layered_services_dest}"
        tar -C "${CYC_BUILD_CYC_APP_DIRECTORY}/cyclone/" -xf "${INPUT_ARTIFACT_CACHE}/link/layered-services"
        touch "${layered_services_dest}/LayeredService_marker"
    fi

    local cdre_input="${INPUT_ARTIFACT_CACHE}/link/cdre-ng"
    local cdre_md5sum
    cdre_md5sum="$(md5sum "${cdre_input}")"
    local cdre_destination="${CYC_BUILD_CYC_APP_CYCLONE_DIRECTORY}"
    local cdre_md5file="${CYC_BUILD_OUTPUT_DIRECTORY}/cdre.md5"
    if /usr/bin/diff -qN "${cdre_md5file}" <(echo -n "${cdre_md5sum}") >/dev/null 2>&1; then
        :
    else
        rm -fr "${cdre_destination}/raid" "${cdre_destination}/xor" "${cdre_destination}/include/cyc_raid_api.h" "${cdre_destination}/include/cyc_raid_error.h" "${cdre_destination}/include/cyc_xor_api.h"
        tar -C "${cdre_destination}" -xf "${cdre_input}"
        echo -n "${cdre_md5sum}" > "${cdre_md5file}"
    fi

    cyc_extract_third_party datapath
    mkdir -p "${CYC_BUILD_TARGET_DIRECTORY}/lib" "${CYC_BUILD_TARGET_DIRECTORY}/bin"
}

configure_datapath() {
    prepare_datapath_tree
    (
        cd "${CYC_BUILD_TARGET_DIRECTORY}"
        local cmd_cmake="cmake -G Ninja -DCMAKE_EXPORT_COMPILE_COMMANDS=ON -DCMAKE_BUILD_TYPE=${CM_BUILD_TYPE} -S ${CYC_BUILD_CYC_APP_CYCLONE_DIRECTORY} -B. -DGCOVOption:BOOL=OFF -DDM_OUTOUT_DIR=${DM_OUTOUT_DIR} -DCMAKE_RULE_MESSAGES=OFF -DENABLE_SANITIZERS=OFF"
        if [[ ! -f build.ninja ]] || ! diff -q <(echo "${cmd_cmake}") .cmd_cmake_saved >/dev/null 2>&1; then
            eval "${cmd_cmake}"
            echo "${cmd_cmake}" > .cmd_cmake_saved
        fi
    )
}

massage_datapath_compile_commands() {
    local dpcc="${TOP}/datapath/${DM_BINARY_DIR}/simulation/compile_commands.json"
    local ccjson="${PDRTOP}/source/datapath/compile_commands.json"

    [[ -f "${dpcc}" ]] || die "datapath compile_commands.json was not generated: ${dpcc}"
    jq '.|=sort_by(."file")' < "${dpcc}" | envsubst > "${ccjson}"
    sed -i \
        -e "s,/[^ ]*/datapath/cyclone/../../dp_common,RESTOREME,g" \
        -e "s,/[^ ]*/datapath/cyclone/../../cyc_platform,RESTOREPL,g" \
        -e "s,/[^ ]*/datapath/cyclone,${PDRTOP}/source/datapath/cyclone,g" \
        -e "s,RESTOREME,${PDRTOP}/source/cyc_core/dp_common -I ${PDRTOP}/source/cdre-ng/src/include,g" \
        -e "s,RESTOREPL,${PDRTOP}/source/cyc_core/cyc_platform,g" \
        "${ccjson}"
    sed -i "s,/[^ ]*/datapath/cyclone/LayeredService,${PDRTOP}/source/layered-services/LayeredService,g" "${ccjson}"
    GENERATED_FRAGMENTS+=("${ccjson}")
}

configure_cyc_core() {
    local ccu_input="${INPUT_ARTIFACT_CACHE}/link/cyc_crypto_util"
    local ccu_md5sum
    ccu_md5sum="$(md5sum "${ccu_input}")"
    local ccu_destination="${TOP}/cyc_platform/src/utils/cyc_crypto_util"
    local ccu_md5file="${ccu_destination}/cyc_crypto_util.md5"

    if /usr/bin/diff -qN "${ccu_md5file}" <(echo -n "${ccu_md5sum}") >/dev/null 2>&1; then
        :
    else
        rm -fr "${ccu_destination}"
        mkdir -p "${ccu_destination}"
        tar -C "${ccu_destination}" -xf "${ccu_input}"
        echo -n "${ccu_md5sum}" > "${ccu_md5file}"
    fi

    cyc_extract_third_party plt
    mkdir -p "${TOP}/cyc_platform/${OBJ_DIR}"
    (
        cd "${TOP}/cyc_platform/${OBJ_DIR}"
        local cmd_cmake="cmake -DCMAKE_BUILD_TYPE=${CM_BUILD_TYPE} -DCMAKE_RULE_MESSAGES=OFF ${CMOPTS} ../src"
        if [[ ! -f Makefile ]] || ! diff -q <(echo "${cmd_cmake}") .cmd_cmake_saved >/dev/null 2>&1; then
            eval "${cmd_cmake}"
            echo "${cmd_cmake}" > .cmd_cmake_saved
        fi
    )
}

massage_cyc_core_compile_commands() {
    local wd="${TOP}/compile_commands"
    local pmcc="${TOP}/cyc_platform/${OBJ_DIR}/compile_commands.json"
    local out="${wd}/compile_commands_pm.json"

    [[ -f "${pmcc}" ]] || die "cyc_core compile_commands.json was not generated: ${pmcc}"
    mkdir -p "${wd}"
    jq '.|=sort_by(."file")' < "${pmcc}" | envsubst > "${out}"
    sed -i "s,/[^ ]*/${OBJ_DIR}/xblock-src,${PDRTOP}/source/xblock,g" "${out}"
    sed -i "s,/[^ ]*/${OBJ_DIR}/nt-nvmeof-frontend,${PDRTOP}/source/nt-nvmeof-frontend/src,g" "${out}"
    GENERATED_FRAGMENTS+=("${out}")
}

write_unified_compile_commands() {
    local wd="${TOP}/compile_commands"
    [[ ${#GENERATED_FRAGMENTS[@]} -gt 0 ]] || die "no compile_commands fragments were generated"
    jq -s 'flatten(1)' "${GENERATED_FRAGMENTS[@]}" > "${wd}/unified_compile_commands.json"
}

REPO_MODE=both
FLAVOR=DEBUG
INSIDE_BUILDER=no
HYDRATE=no
WORKSPACE_ROOT_OVERRIDE=
GENERATED_FRAGMENTS=()

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
        --inside-builder)
            INSIDE_BUILDER=yes
            shift
            ;;
        --hydrate)
            HYDRATE=yes
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
PDRTOP=$(resolve_workspace_root)
HYDRATE_SCRIPT=$(resolve_hydrate_script)
TOP="${PDRTOP}/source/cyc_core"
OUTPUT_ROOT="${PDRTOP}/output_${FLAVOR}"
INPUT_ARTIFACT_CACHE="${TOP}/.dmcache"
DM_OUTOUT_DIR="${OUTPUT_ROOT}/cyc_core-dm_compile"
DEVOPS_BUILD_FLAVOR="${FLAVOR}"
FLAVOR_LC=${FLAVOR,,}
BUILDER_IMAGE_FILE="${OUTPUT_ROOT}/docker-images/sles15sp6-sles_builder/sles15sp6-sles_builder.docker"

case "${FLAVOR}" in
    DEBUG)
        CM_BUILD_TYPE=Debug
        OBJ_DIR=obj_Debug
        DM_BINARY_DIR=debug
        ENABLEFAULTINJECTIONOption=ON
        ENABLEPNVMETDATAVERIFICATIONOption=ON
        ENABLEPNVMETADDPOISONOption=ON
        ;;
    RETAIL)
        CM_BUILD_TYPE=Release
        OBJ_DIR=obj_Release
        DM_BINARY_DIR=release
        ENABLEFAULTINJECTIONOption=OFF
        ENABLEPNVMETDATAVERIFICATIONOption=OFF
        ENABLEPNVMETADDPOISONOption=OFF
        ;;
esac

populate_inputs
maybe_hydrate_inputs
restore_missing_inputs_from_cache
materialize_missing_inputs_from_cache
restore_missing_inputs_from_cache
ensure_local_tooling_or_reexec
require_tool cmake
require_tool ninja
require_tool jq
require_tool envsubst
require_tool pigz
export PDRTOP TOP INPUT_ARTIFACT_CACHE DEVOPS_BUILD_FLAVOR DM_OUTOUT_DIR
export DEVOPS_GITHUB_TOKEN="${DEVOPS_GITHUB_TOKEN:-}"
export DEVOPS_GITHUB_SERVER="${DEVOPS_GITHUB_SERVER:-}"
export DEVOPS_ARTIFACTORY_SERVER="${DEVOPS_ARTIFACTORY_SERVER:-}"

[[ -f "${TOP}/env.properties" ]] || die "missing ${TOP}/env.properties"
[[ -f "${TOP}/version.txt" ]] || die "missing ${TOP}/version.txt"
source "${TOP}/env.properties"
set +u
source "${TOP}/version.txt"
set -u

CMOPTS="-DGCOVOption:BOOL=OFF"
CMOPTS="${CMOPTS} -DCMAKE_EXPORT_COMPILE_COMMANDS=ON"
CMOPTS="${CMOPTS} -DENABLEFAULTINJECTIONOption:BOOL=${ENABLEFAULTINJECTIONOption}"
CMOPTS="${CMOPTS} -DENABLEPNVMETDATAVERIFICATIONOption:BOOL=${ENABLEPNVMETDATAVERIFICATIONOption}"
CMOPTS="${CMOPTS} -DENABLEPNVMETADDPOISONOption:BOOL=${ENABLEPNVMETADDPOISONOption}"
CMOPTS="${CMOPTS} -DDM_OUTOUT_DIR=${DM_OUTOUT_DIR}"
CMOPTS="${CMOPTS} -DARTIFACT_CACHE=${INPUT_ARTIFACT_CACHE}"
CMOPTS="${CMOPTS} -DGITHUB_TOKEN=${DEVOPS_GITHUB_TOKEN}"
CMOPTS="${CMOPTS} -DGITHUB_SERVER=${DEVOPS_GITHUB_SERVER}"

prepare_dmcache
mkdir -p "${TOP}/compile_commands" "${DM_OUTOUT_DIR}"

case "${REPO_MODE}" in
    datapath)
        configure_datapath
        massage_datapath_compile_commands
        ;;
    cyc_core)
        configure_cyc_core
        massage_cyc_core_compile_commands
        ;;
    both)
        configure_datapath
        massage_datapath_compile_commands
        configure_cyc_core
        massage_cyc_core_compile_commands
        ;;
esac

write_unified_compile_commands

echo "Generated compile commands:"
for fragment in "${GENERATED_FRAGMENTS[@]}"; do
    echo "  ${fragment}"
done
echo "  ${TOP}/compile_commands/unified_compile_commands.json"
