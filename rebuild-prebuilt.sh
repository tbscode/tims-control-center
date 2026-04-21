#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUILD_DIR="${BUILD_DIR:-${ROOT_DIR}/_build_local}"
INSTALL_PREFIX="${INSTALL_PREFIX:-/tmp/tims-cc-install}"

echo "[1/4] Building in nix develop shell"
nix develop nixpkgs#gnome-control-center -c bash -lc "
  set -euo pipefail
  cd '${ROOT_DIR}'
  rm -rf '${BUILD_DIR}' '${INSTALL_PREFIX}'
  meson setup '${BUILD_DIR}' --prefix='${INSTALL_PREFIX}'
  meson compile -C '${BUILD_DIR}'
  meson install -C '${BUILD_DIR}'
"

echo "[2/4] Refreshing prebuilt payload"
rm -rf \
  "${ROOT_DIR}/prebuilt/bin" \
  "${ROOT_DIR}/prebuilt/lib" \
  "${ROOT_DIR}/prebuilt/libexec" \
  "${ROOT_DIR}/prebuilt/share"
cp -a \
  "${INSTALL_PREFIX}/bin" \
  "${INSTALL_PREFIX}/lib" \
  "${INSTALL_PREFIX}/libexec" \
  "${INSTALL_PREFIX}/share" \
  "${ROOT_DIR}/prebuilt/"

echo "[3/4] Rebuilding package"
(cd "${ROOT_DIR}" && nix build .)

echo "[4/4] Cleaning local build artifacts"
rm -rf "${BUILD_DIR}" "${ROOT_DIR}/result"

echo "Done. Verify with: control-center-hypr --custom"
