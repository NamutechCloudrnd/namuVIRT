#!/usr/bin/env bash
# Ubuntu deb 빌드 본체. 엔트리: ./build/ubuntu.sh
# packaging/<ubuntuXXXX>/debian 을 루트 debian/ 에 임시 교체 → packaging/build-deb.sh -o
# 로 build/packages/deb/<ubuntuXXXX>/latest/ 에 직접 출력 → debian/ 원복.

set -Eeuo pipefail

: "${NAMUVIRT_SCRIPT_TAG:?NAMUVIRT_SCRIPT_TAG required}"
: "${NAMUVIRT_BUILD_DIR:?NAMUVIRT_BUILD_DIR required}"
: "${NAMUVIRT_REPO_ROOT:?NAMUVIRT_REPO_ROOT required}"

LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${LIB_DIR}/common.sh"

# 빌드 호스트 OS 로 기본 dist 결정 (Ubuntu 24.04 → ubuntu2404, 26.04 → ubuntu2604).
DEB_DIST="${DEB_DIST:-$(ubuntu_dist_id)}"
DEB_DIST="${DEB_DIST:-ubuntu}"
OUT_DIR="${BUILD_DIR}/packages/deb/${DEB_DIST}/latest"
UI_NODE_MIN_MAJOR=18
# 빌드에 쓸 debian 디렉터리 (select_debian_dir 이 채움). packaging/<dist>/debian 없으면 루트 debian/.
DEBIAN_SRC_DIR=""
DEBIAN_BACKUP_DIR=""

# --help 출력.
usage() {
  cat <<'USAGE'
Usage:
  ./build/ubuntu.sh [--mode normal|dev|clean] [--without-vmware] [--no-auto-deps] [--dry-run]

Builds the current namuVIRT tree as Debian packages via packaging/build-deb.sh.
Output: build/packages/deb/<ubuntu2404|ubuntu2604>/latest/

Never runs git checkout, git reset, or git clean.
Every run: install missing host deps → full deb build → fresh output under build/packages/.
packaging/<dist>/debian is swapped into debian/ for the build and restored afterwards
  (falls back to the root debian/ with a warning when no per-OS directory exists).
Missing build tools on Ubuntu: auto-install via build/lib/deps-ubuntu.sh
  (disable with --no-auto-deps or SKIP_ENSURE_BUILD_DEPS=1; sudo may be used).

Environment:
  NON_OSS_DIR   default: vendor/cloudstack-nonoss
  DEB_DIST      default: ubuntu<VERSION_ID without dot> (e.g. ubuntu2604)
USAGE
}

# ACS_BUILD_OPTS 에 Maven 옵션 중복 없이 추가.
append_acs_build_opt() {
  local opt="$1"
  case " ${ACS_BUILD_OPTS:-} " in
    *" ${opt} "*) ;;
    *) export ACS_BUILD_OPTS="${ACS_BUILD_OPTS:+${ACS_BUILD_OPTS} }${opt}" ;;
  esac
}

# DEB_BUILD_OPTIONS·ACS_BUILD_OPTS·NODE_OPTIONS 설정 (noredist/skipTests).
configure_build_options() {
  case "${MODE}" in
    clean) export DEB_BUILD_OPTIONS="" ;;
    normal|dev)
      export DEB_BUILD_OPTIONS="nocheck"
      append_acs_build_opt "-DskipTests"
      ;;
  esac
  if [ "${WITH_VMWARE}" -eq 1 ]; then
    append_acs_build_opt "-Dnoredist"
  fi
  detect_ui_node_openssl_option
  log "DEB_BUILD_OPTIONS=${DEB_BUILD_OPTIONS:-}"
  log "ACS_BUILD_OPTS=${ACS_BUILD_OPTS:-}"
}

# Ubuntu 빌드 도구 누락 시 deps-ubuntu.sh 자동 호출.
ensure_build_dependencies() {
  ensure_build_deps_script "${LIB_DIR}/deps-ubuntu.sh"
}

# dch·dpkg-buildpackage·mvn 등 Ubuntu deb 빌드 필수 도구 확인.
verify_ubuntu_build_tools() {
  if [ "${DRY_RUN}" -eq 1 ]; then
    log "verify ubuntu build tools: dch mvn>=3.6.3 node npm jar"
    return 0
  fi
  if [ -x /opt/maven/bin/mvn ]; then
    export PATH="/opt/maven/bin:${PATH}"
  fi
  command -v dch >/dev/null 2>&1 || die "dch not found — run without --no-auto-deps or: sudo ./build/lib/deps-ubuntu.sh"
  command -v dpkg-buildpackage >/dev/null 2>&1 || die "dpkg-buildpackage not found — sudo ./build/lib/deps-ubuntu.sh"
  command -v mvn >/dev/null 2>&1 || die "mvn not found — sudo ./build/lib/deps-ubuntu.sh"
  local mvn_ver min_ok
  mvn_ver="$(mvn -version 2>/dev/null | awk '/Apache Maven/{print $3; exit}')"
  [ -n "${mvn_ver}" ] || die "unable to parse mvn version"
  min_ok="$(printf '%s\n' '3.6.3' "${mvn_ver}" | sort -V | head -1)"
  [ "${min_ok}" = "3.6.3" ] || die "Maven ${mvn_ver} is too old; need >= 3.6.3"
  command -v node >/dev/null 2>&1 || die "node not found"
  command -v npm >/dev/null 2>&1 || die "npm not found"
  [ "$(node_major_version)" -ge "${UI_NODE_MIN_MAJOR}" ] \
    || die "node $(node -v) is too old; need >= ${UI_NODE_MIN_MAJOR}"
  log "ui build node: $(command -v node) $(node -v)"
  command -v jar >/dev/null 2>&1 || die "jar not found — openjdk-17-jdk required"
}

# webpack 4 는 md4 해시를 쓰는데 OpenSSL 3 은 기본 차단 → 필요할 때만 NODE_OPTIONS 에 --openssl-legacy-provider.
detect_ui_node_openssl_option() {
  local md4_js='require("crypto").createHash("md4")'
  if [ "${DRY_RUN}" -eq 1 ]; then
    log "detect node md4 support (--openssl-legacy-provider if needed)"
    return 0
  fi
  if node -e "${md4_js}" >/dev/null 2>&1; then
    return 0
  fi
  if node --openssl-legacy-provider -e "${md4_js}" >/dev/null 2>&1; then
    export NODE_OPTIONS="${NODE_OPTIONS:+${NODE_OPTIONS} }--openssl-legacy-provider"
    log "ui build node: OpenSSL 3 md4 disabled — NODE_OPTIONS=${NODE_OPTIONS}"
    return 0
  fi
  die "node cannot create md4 hash (needed by webpack 4), even with --openssl-legacy-provider"
}

# packaging/<dist>/debian 이 있으면 사용, 없으면 루트 debian/ (경고).
select_debian_dir() {
  local candidate="${REPO_DIR}/packaging/${DEB_DIST}/debian"
  if [ -d "${candidate}" ]; then
    DEBIAN_SRC_DIR="${candidate}"
  else
    DEBIAN_SRC_DIR="${REPO_DIR}/debian"
    warn "packaging/${DEB_DIST}/debian not found — building with root debian/"
  fi
  log "debian dir: ${DEBIAN_SRC_DIR#"${REPO_DIR}/"}"
}

# 사용할 changelog 첫 항목 버전이 pom.xml 버전과 같은지 확인 (OS별 changelog 누락 갱신 방지).
verify_changelog_version() {
  local changelog="${DEBIAN_SRC_DIR}/changelog" deb_ver pom_ver
  [ -f "${changelog}" ] || die "changelog not found: ${changelog}"
  deb_ver="$(head -n1 "${changelog}" | awk -F '[()]' '{print $2}')"
  pom_ver="$(grep '<version>' "${REPO_DIR}/pom.xml" | head -2 | tail -1 | cut -d'>' -f2 | cut -d'<' -f1)"
  [ -n "${deb_ver}" ] || die "unable to parse version from ${changelog}"
  [ "${deb_ver}" = "${pom_ver}" ] \
    || die "version mismatch: ${changelog#"${REPO_DIR}/"} (${deb_ver}) != pom.xml (${pom_ver})"
  log "changelog version ${deb_ver} matches pom.xml"
}

# 루트 debian/ 을 백업하고 DEBIAN_SRC_DIR 로 교체 (루트 debian/ 을 쓰면 아무것도 안 함).
swap_in_debian_dir() {
  [ "${DEBIAN_SRC_DIR}" = "${REPO_DIR}/debian" ] && return 0
  if [ "${DRY_RUN}" -eq 1 ]; then
    log "swap debian/ <- ${DEBIAN_SRC_DIR#"${REPO_DIR}/"} (restored after build)"
    return 0
  fi
  DEBIAN_BACKUP_DIR="$(mktemp -d)"
  trap restore_debian_dir EXIT
  trap 'exit 130' INT
  trap 'exit 143' TERM
  cp -a "${REPO_DIR}/debian" "${DEBIAN_BACKUP_DIR}/debian"
  rm -rf "${REPO_DIR}/debian"
  cp -a "${DEBIAN_SRC_DIR}" "${REPO_DIR}/debian"
  log "debian/ <- ${DEBIAN_SRC_DIR#"${REPO_DIR}/"} (original backed up to ${DEBIAN_BACKUP_DIR})"
}

# 빌드 종료(성공·실패·중단) 시 원래 debian/ 복원.
restore_debian_dir() {
  [ -n "${DEBIAN_BACKUP_DIR}" ] && [ -d "${DEBIAN_BACKUP_DIR}/debian" ] || return 0
  rm -rf "${REPO_DIR}/debian"
  cp -a "${DEBIAN_BACKUP_DIR}/debian" "${REPO_DIR}/debian"
  rm -rf "${DEBIAN_BACKUP_DIR}"
  DEBIAN_BACKUP_DIR=""
  log "debian/ restored"
}

# build-deb.sh 가 OUT_DIR 에 떨군 runtime deb 5종 존재 확인.
collect_runtime_packages() {
  local pkg deb
  for pkg in "${RUNTIME_PKGS[@]}"; do
    if [ "${DRY_RUN}" -eq 1 ]; then
      log "require ${OUT_DIR}/${pkg}_*.deb"
      continue
    fi
    deb="$(find "${OUT_DIR}" -maxdepth 1 -type f -name "${pkg}_*.deb" | sort | tail -1 || true)"
    [ -n "${deb}" ] || die "missing built package: ${pkg}_*.deb in ${OUT_DIR}"
    log "found ${deb}"
  done
}

# ── Main ──────────────────────────────────────────────────────────

build_parse_common_args "$@" || { usage; exit 0; }

[ -f "${REPO_DIR}/packaging/build-deb.sh" ] || die "packaging/build-deb.sh not found in ${REPO_DIR}"

build_preflight_repo
BUILD_ID="$(date +%Y%m%d_%H%M%S)"

log "repo=${REPO_DIR}"
log "branch=${BRANCH}"
log "build-mode=${MODE}"
log "with-vmware=${WITH_VMWARE}"
log "deb-dist=${DEB_DIST}"
log "output=${OUT_DIR}"
log "execution=$([ "${DRY_RUN}" -eq 1 ] && echo dry-run || echo apply)"

select_debian_dir
verify_changelog_version
ensure_build_dependencies
verify_java17_jdk
ensure_vmware_non_oss_deps
verify_ubuntu_build_tools
run mkdir -p "${LOG_DIR}"
prepare_fresh_output_dir "${OUT_DIR}"
configure_build_options
swap_in_debian_dir

log "build command: packaging/build-deb.sh -o ${OUT_DIR}"
if [ "${DRY_RUN}" -eq 0 ]; then
  (cd "${REPO_DIR}" && bash packaging/build-deb.sh -o "${OUT_DIR}")
fi
restore_debian_dir

collect_runtime_packages
if [ "${DRY_RUN}" -eq 0 ]; then
  mgmt_deb="$(find "${OUT_DIR}" -maxdepth 1 -type f -name 'cloudstack-management_*.deb' | sort | tail -1 || true)"
  [ -n "${mgmt_deb}" ] && verify_vmware_artifacts_in_archive "${mgmt_deb}" deb
fi
write_build_metadata deb deb

log "done"
