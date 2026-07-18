#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PZ_JAR="${PZ_JAR:-/home/cjstorrs/games/Project Zomboid Linux 42.19.0/game/projectzomboid/projectzomboid.jar}"
ZOMBIE_BUDDY_JAR="${ZOMBIE_BUDDY_JAR:-/home/cjstorrs/games/Project Zomboid Linux 42.19.0/game/projectzomboid/ZombieBuddy.jar}"
PZ_JAVA="${PZ_JAVA:-$(dirname "${PZ_JAR}")/jre64/bin/java}"
BUILD_DIR="${ROOT_DIR}/.build"
OUT_JAR="${ROOT_DIR}/42/media/java/cjsFastTravelWaypoints.jar"

for required_jar in "${PZ_JAR}" "${ZOMBIE_BUDDY_JAR}"; do
    if [[ ! -f "${required_jar}" ]]; then
        echo "Required jar not found: ${required_jar}" >&2
        exit 1
    fi
done
if [[ ! -x "${PZ_JAVA}" ]]; then
    echo "Project Zomboid Java runtime not found: ${PZ_JAVA}" >&2
    exit 1
fi

rm -rf "${BUILD_DIR}"
mkdir -p "${BUILD_DIR}/classes" "${BUILD_DIR}/linkage-test" "$(dirname "${OUT_JAR}")"

mapfile -t JAVA_SOURCES < <(find "${ROOT_DIR}/src/stubs/java" "${ROOT_DIR}/src/main/java" -name '*.java' | sort)

javac --release 17 \
    -classpath "${ZOMBIE_BUDDY_JAR}" \
    -d "${BUILD_DIR}/classes" \
    "${JAVA_SOURCES[@]}"

rm -rf "${BUILD_DIR}/classes/org" "${BUILD_DIR}/classes/se" "${BUILD_DIR}/classes/zombie"

jar --create \
    --file "${OUT_JAR}" \
    --date=2024-01-01T00:00:00Z \
    -C "${BUILD_DIR}/classes" com

python3 -m zipfile -t "${OUT_JAR}" >/dev/null

mapfile -t LINKAGE_TEST_SOURCES < <(find "${ROOT_DIR}/src/linkageTest/java" -name '*.java' | sort)
javac --release 17 \
    -d "${BUILD_DIR}/linkage-test" \
    "${LINKAGE_TEST_SOURCES[@]}"

"${PZ_JAVA}" -ea \
    -classpath "${BUILD_DIR}/linkage-test:${OUT_JAR}:${ZOMBIE_BUDDY_JAR}:${PZ_JAR}" \
    com.cjstorrs.cjsfasttravelwaypoints.GameApiLinkageTest

echo "Built ${OUT_JAR}"
