#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PARTS_DIR="${1:-${ROOT_DIR}/dist/parts}"
OUTPUT_DIR="${2:-${ROOT_DIR}/dist/release}"

RUNTIME_ID="java25-macos-exso.2"
JAVA_VERSION="25.0.1"
ASSET_NAME="java_macos_exso-25.0.1-exso.2.jar"
MANIFEST_NAME="java25-macos-exso.json"
MODULES_CSV="java.base,java.datatransfer,java.xml,java.prefs,java.desktop,java.logging,jdk.accessibility,jdk.crypto.ec,jdk.unsupported,java.instrument,java.management,java.naming,java.sql,java.scripting,java.rmi,jdk.attach,jdk.compiler,jdk.httpserver,jdk.jdi"
DOWNLOAD_URL="https://github.com/QuiteSimplyTheGoat/urban-giggle/releases/download/${RUNTIME_ID}/${ASSET_NAME}"

resolve_runtime_dir() {
  local arch="$1"
  local base="${PARTS_DIR}/java_vm-${arch}"
  if [[ -f "${base}/bin/java" ]]; then
    printf '%s\n' "${base}"
    return 0
  fi
  if [[ -f "${base}/java_vm-${arch}/bin/java" ]]; then
    printf '%s\n' "${base}/java_vm-${arch}"
    return 0
  fi
  echo "Missing ${arch} runtime under ${base}" >&2
  find "${base}" -maxdepth 3 -type f -o -type d 2>/dev/null | sort >&2 || true
  return 1
}

restore_runtime_permissions() {
  local runtime="$1"
  find "${runtime}/bin" -type f -exec chmod +x {} \;
  find "${runtime}/lib" -type f \( -name '*.dylib' -o -name 'jspawnhelper' \) -exec chmod +x {} \;
}

X64_RUNTIME="$(resolve_runtime_dir x64)"
ARM_RUNTIME="$(resolve_runtime_dir aarch64)"
UNIVERSAL_ROOT="${ROOT_DIR}/build/universal"
UNIVERSAL_RUNTIME="${UNIVERSAL_ROOT}/java_vm"
MODULES_LIST="${UNIVERSAL_ROOT}/modules-universal.txt"

restore_runtime_permissions "${X64_RUNTIME}"
restore_runtime_permissions "${ARM_RUNTIME}"

rm -rf "${UNIVERSAL_ROOT}" "${OUTPUT_DIR}"
mkdir -p "${UNIVERSAL_ROOT}" "${OUTPUT_DIR}"

cp -R "${X64_RUNTIME}" "${UNIVERSAL_RUNTIME}"

while IFS= read -r -d '' x64_file; do
  relative_path="${x64_file#${X64_RUNTIME}/}"
  arm_file="${ARM_RUNTIME}/${relative_path}"
  out_file="${UNIVERSAL_RUNTIME}/${relative_path}"
  if [[ ! -f "${arm_file}" ]]; then
    continue
  fi
  if file "${x64_file}" | grep -q 'Mach-O' && file "${arm_file}" | grep -q 'Mach-O'; then
    lipo -create "${x64_file}" "${arm_file}" -output "${out_file}.tmp"
    chmod --reference="${x64_file}" "${out_file}.tmp" 2>/dev/null || chmod "$(stat -f %Lp "${x64_file}")" "${out_file}.tmp"
    mv "${out_file}.tmp" "${out_file}"
  fi
done < <(find "${X64_RUNTIME}" -type f -print0)

cat > "${UNIVERSAL_RUNTIME}/exso-runtime.properties" <<EOF
runtimeId=${RUNTIME_ID}
javaVersion=${JAVA_VERSION}
universalMachO=true
modules=${MODULES_CSV}
EOF

restore_runtime_permissions "${UNIVERSAL_RUNTIME}"

if [[ -f "${UNIVERSAL_RUNTIME}/release" ]]; then
  awk -F= '$1 != "OS_ARCH" { print }' "${UNIVERSAL_RUNTIME}/release" > "${UNIVERSAL_RUNTIME}/release.tmp"
  mv "${UNIVERSAL_RUNTIME}/release.tmp" "${UNIVERSAL_RUNTIME}/release"
fi

"${UNIVERSAL_RUNTIME}/bin/java" --list-modules | tee "${MODULES_LIST}"

IFS=',' read -r -a REQUIRED_MODULES <<< "${MODULES_CSV}"
for required in "${REQUIRED_MODULES[@]}"; do
  if ! grep -q "^${required}@" "${MODULES_LIST}"; then
    echo "Universal runtime is missing ${required}" >&2
    exit 1
  fi
done

for binary in \
  "${UNIVERSAL_RUNTIME}/bin/java" \
  "${UNIVERSAL_RUNTIME}/lib/libjava.dylib" \
  "${UNIVERSAL_RUNTIME}/lib/server/libjvm.dylib"; do
  file "${binary}"
  lipo -info "${binary}" | grep -q 'x86_64'
  lipo -info "${binary}" | grep -q 'arm64'
done

(
  cd "${UNIVERSAL_ROOT}"
  zip -qry "${OUTPUT_DIR}/${ASSET_NAME}" java_vm
)

SHA256="$(shasum -a 256 "${OUTPUT_DIR}/${ASSET_NAME}" | awk '{print $1}')"
SIZE="$(stat -f %z "${OUTPUT_DIR}/${ASSET_NAME}")"
printf '%s  %s\n' "${SHA256}" "${ASSET_NAME}" > "${OUTPUT_DIR}/${ASSET_NAME}.sha256"

python3 - <<PY
import json
from datetime import datetime, timezone
from pathlib import Path

output = Path("${OUTPUT_DIR}") / "${MANIFEST_NAME}"
modules = "${MODULES_CSV}".split(",")
manifest = {
    "runtimeId": "${RUNTIME_ID}",
    "javaVersion": "${JAVA_VERSION}",
    "assetName": "${ASSET_NAME}",
    "downloadUrl": "${DOWNLOAD_URL}",
    "sha256": "${SHA256}",
    "size": int("${SIZE}"),
    "modules": modules,
    "universalMachO": True,
    "publishedAt": datetime.now(timezone.utc).isoformat().replace("+00:00", "Z"),
}
output.write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")
PY

echo "Created ${OUTPUT_DIR}/${ASSET_NAME}"
echo "Created ${OUTPUT_DIR}/${MANIFEST_NAME}"
