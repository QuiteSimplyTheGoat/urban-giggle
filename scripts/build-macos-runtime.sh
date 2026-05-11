#!/usr/bin/env bash
set -euo pipefail

ARCH="${1:?usage: build-macos-runtime.sh <x64|aarch64> <output-dir>}"
OUTPUT_DIR="${2:?usage: build-macos-runtime.sh <x64|aarch64> <output-dir>}"

JAVA_VERSION="25.0.1"
JDK_BUILD_PATH="2fbf10d8c78e40bd87641c434705079d/8/GPL"
MODULES="java.base,java.datatransfer,java.xml,java.prefs,java.desktop,java.logging,jdk.accessibility,jdk.crypto.ec,jdk.unsupported,java.instrument,java.management"

case "${ARCH}" in
  x64)
    JDK_ARCH="x64"
    ;;
  aarch64)
    JDK_ARCH="aarch64"
    ;;
  *)
    echo "Unsupported architecture: ${ARCH}" >&2
    exit 2
    ;;
esac

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORK_DIR="${ROOT_DIR}/build/${ARCH}"
RUNTIME_DIR="${OUTPUT_DIR}/java_vm-${ARCH}"
JDK_URL="https://download.java.net/java/GA/jdk${JAVA_VERSION}/${JDK_BUILD_PATH}/openjdk-${JAVA_VERSION}_macos-${JDK_ARCH}_bin.tar.gz"

rm -rf "${WORK_DIR}" "${RUNTIME_DIR}"
mkdir -p "${WORK_DIR}" "${OUTPUT_DIR}"

echo "Downloading ${JDK_URL}"
curl -fL --retry 3 --retry-delay 5 "${JDK_URL}" -o "${WORK_DIR}/jdk.tar.gz"
tar -xzf "${WORK_DIR}/jdk.tar.gz" -C "${WORK_DIR}"

JDK_HOME="$(find "${WORK_DIR}" -type d -path '*/Contents/Home' | head -n 1)"
if [[ -z "${JDK_HOME}" ]]; then
  echo "Could not locate extracted JDK Contents/Home" >&2
  exit 1
fi

"${JDK_HOME}/bin/jlink" \
  --module-path "${JDK_HOME}/jmods" \
  --add-modules "${MODULES}" \
  --output "${RUNTIME_DIR}" \
  --strip-debug \
  --no-man-pages \
  --no-header-files

cat > "${RUNTIME_DIR}/exso-runtime.properties" <<EOF
runtimeId=java25-macos-exso.1
javaVersion=${JAVA_VERSION}
arch=${ARCH}
modules=${MODULES}
EOF

"${RUNTIME_DIR}/bin/java" --list-modules | tee "${OUTPUT_DIR}/modules-${ARCH}.txt"

for required in java.instrument java.management java.desktop jdk.unsupported; do
  if ! grep -q "^${required}@" "${OUTPUT_DIR}/modules-${ARCH}.txt"; then
    echo "jlink output is missing ${required}" >&2
    exit 1
  fi
done

for binary in "${RUNTIME_DIR}/bin/java" "${RUNTIME_DIR}/lib/server/libjvm.dylib"; do
  file "${binary}"
done
