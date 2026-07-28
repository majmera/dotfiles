#!/usr/bin/env bash
set -euo pipefail

usage() {
    cat <<'EOF'
Usage: install_emacs.sh [--version VERSION] [--prefix DIR] [--jobs N]

Build and install a user-local, terminal-only Emacs from GNU source.
Defaults to the latest stable release published at https://ftp.gnu.org/gnu/emacs/.

Examples:
  ./scripts/install_emacs.sh
  ./scripts/install_emacs.sh --version 30.2
  ./scripts/install_emacs.sh --prefix "$HOME/.local/opt"
EOF
}

die() {
    echo "ERROR: $*" >&2
    exit 1
}

require_tool() {
    command -v "$1" >/dev/null 2>&1 || die "missing required tool: $1"
}

latest_emacs_version() {
    python3 - <<'PY'
import re
import urllib.request
html = urllib.request.urlopen('https://ftp.gnu.org/gnu/emacs/').read().decode()
versions = sorted(
    set(re.findall(r'emacs-(\d+\.\d+)\.tar\.xz', html)),
    key=lambda s: tuple(map(int, s.split('.'))),
)
if not versions:
    raise SystemExit('unable to determine latest Emacs release')
print(versions[-1])
PY
}

VERSION=
PREFIX_ROOT="${HOME}/.local/opt"
JOBS=${EMACS_BUILD_JOBS:-$(getconf _NPROCESSORS_ONLN 2>/dev/null || echo 4)}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --version)
            [[ $# -ge 2 ]] || die "--version requires a value"
            VERSION=$2
            shift 2
            ;;
        --prefix)
            [[ $# -ge 2 ]] || die "--prefix requires a value"
            PREFIX_ROOT=$2
            shift 2
            ;;
        --jobs)
            [[ $# -ge 2 ]] || die "--jobs requires a value"
            JOBS=$2
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

require_tool curl
require_tool tar
require_tool make
require_tool gcc
require_tool pkg-config
require_tool install
require_tool python3

if [[ -z "${VERSION}" ]]; then
    VERSION=$(latest_emacs_version)
fi

ARCHIVE="emacs-${VERSION}.tar.xz"
URL="https://ftp.gnu.org/gnu/emacs/${ARCHIVE}"
BUILD_ROOT="${HOME}/.cache/emacs-build"
SRC_DIR="${BUILD_ROOT}/emacs-${VERSION}"
PREFIX_DIR="${PREFIX_ROOT}/emacs-${VERSION}"
CURRENT_LINK="${PREFIX_ROOT}/emacs-current"
BIN_DIR="${HOME}/.local/bin"
TARBALL="${BUILD_ROOT}/${ARCHIVE}"

mkdir -p "${BUILD_ROOT}" "${PREFIX_ROOT}" "${BIN_DIR}"

if [[ ! -f "${TARBALL}" ]]; then
    echo "Downloading ${URL}"
    curl -fL "${URL}" -o "${TARBALL}"
fi

rm -rf "${SRC_DIR}"
tar -C "${BUILD_ROOT}" -xf "${TARBALL}"
cd "${SRC_DIR}"

CONFIGURE_ARGS=(
    --prefix="${PREFIX_DIR}"
    --without-x
    --without-sound
    --without-dbus
    --without-gsettings
    --with-mailutils
    --with-gnutls=ifavailable
    --with-native-compilation=no
    --with-tree-sitter=ifavailable
)

echo "Configuring Emacs ${VERSION}"
./configure "${CONFIGURE_ARGS[@]}"

echo "Building Emacs ${VERSION}"
make -j"${JOBS}"

echo "Installing Emacs ${VERSION} into ${PREFIX_DIR}"
make install

ln -sfn "${PREFIX_DIR}" "${CURRENT_LINK}"
ln -sfn "${CURRENT_LINK}/bin/emacs" "${BIN_DIR}/emacs"
ln -sfn "${CURRENT_LINK}/bin/emacsclient" "${BIN_DIR}/emacsclient"
ln -sfn "${CURRENT_LINK}/bin/ctags" "${BIN_DIR}/ctags"
ln -sfn "${CURRENT_LINK}/bin/ebrowse" "${BIN_DIR}/ebrowse"
ln -sfn "${CURRENT_LINK}/bin/etags" "${BIN_DIR}/etags"

"${BIN_DIR}/emacs" --version | head -n 1
