#!/usr/bin/env bash
# 빌더 컨테이너 엔트리: SRC_DIR(레포 마운트) → WORK_DIR 복사 → OS 별 빌드 스크립트 → 패키지를 OUT_DIR 로.
#   Rocky: ./build/rocky.sh  → build/packages/rpm/.
#   Ubuntu: ./build/ubuntu.sh → build/packages/deb/.
# 인자는 그대로 빌드 스크립트에 전달 (예: --without-vmware, --mode clean).

set -Eeuo pipefail

: "${SRC_DIR:=/src}"
: "${WORK_DIR:=/work}"
: "${OUT_DIR:=/out}"

log() { printf '[build/docker] %s\n' "$*"; }
die() { printf '[build/docker] ERROR: %s\n' "$*" >&2; exit 1; }

os_id="$(. /etc/os-release && printf '%s' "${ID:-}")"
case "${os_id}" in
  rocky) build_script=rocky.sh; pkg_subdir=rpm ;;
  ubuntu) build_script=ubuntu.sh; pkg_subdir=deb ;;
  *) die "unsupported builder OS: ${os_id:-unknown}" ;;
esac

[ -x "${SRC_DIR}/build/${build_script}" ] || die "mount the namuVIRT repo at ${SRC_DIR} (missing build/${build_script})"

# 마운트된 소스는 읽기 전용일 수 있으므로 작업 디렉터리에서 빌드한다.
log "sync ${SRC_DIR}/ -> ${WORK_DIR}/"
mkdir -p "${WORK_DIR}"
rsync -a --delete \
  --exclude /dist/ --exclude /build/packages/ --exclude /build/logs/ \
  --exclude /ui/node_modules/ \
  "${SRC_DIR}/" "${WORK_DIR}/"

# 호스트 UID 소유 레포라 git 의 dubious ownership 검사를 끈다 (BUILD_INFO 커밋 기록용).
git config --global --add safe.directory '*'

cd "${WORK_DIR}"
"./build/${build_script}" "$@"

mkdir -p "${OUT_DIR}"
cp -a "${WORK_DIR}/build/packages/${pkg_subdir}/." "${OUT_DIR}/"
log "packages copied to ${OUT_DIR}/"
