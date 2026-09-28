#!/usr/bin/env bash
# Rocky RPM / Ubuntu deb 빌드 공통 헬퍼.
# 경로: REPO_ROOT=레포 루트, BUILD_DIR=build/, NON_OSS_DIR=vendor/cloudstack-nonoss

set -Eeuo pipefail

LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUILD_DIR="${NAMUVIRT_BUILD_DIR:-$(cd "${LIB_DIR}/.." && pwd)}"
REPO_ROOT="${NAMUVIRT_REPO_ROOT:-$(cd "${BUILD_DIR}/.." && pwd)}"
REPO_DIR="${REPO_DIR:-${REPO_ROOT}}"
NON_OSS_DIR="${NON_OSS_DIR:-${NONOSS_DEPS_DIR:-${REPO_ROOT}/vendor/cloudstack-nonoss}}"
LOG_DIR="${BUILD_DIR}/logs"

RUNTIME_PKGS=(cloudstack-common cloudstack-management cloudstack-agent cloudstack-ui cloudstack-usage)

# 로그 한 줄 출력.
log() { printf '[%s] %s\n' "${NAMUVIRT_SCRIPT_TAG:-build}" "$*"; }
# 경고 로그 (stderr).
warn() { printf '[%s] WARN: %s\n' "${NAMUVIRT_SCRIPT_TAG:-build}" "$*" >&2; }
# 에러 메시지 후 종료.
die() { printf '[%s] ERROR: %s\n' "${NAMUVIRT_SCRIPT_TAG:-build}" "$*" >&2; exit 1; }

# 명령을 '+ cmd' 형태로 출력; DRY_RUN=1 이면 실행 생략.
run() {
  printf '+'
  for arg in "$@"; do printf ' %q' "$arg"; done
  printf '\n'
  [ "${DRY_RUN:-0}" -eq 1 ] && return 0
  "$@"
}

# root 권한 확인 (DRY_RUN 이면 생략).
require_root() {
  [ "${DRY_RUN:-0}" -eq 1 ] && return 0
  [ "$(id -u)" -eq 0 ] || die "run as root"
}

# deps-*.sh 를 root 또는 sudo 로 실행.
run_build_deps_installer() {
  local script="$1"
  if [ "${DRY_RUN:-0}" -eq 1 ]; then
    return 0
  fi
  if [ "$(id -u)" -eq 0 ]; then
    bash "${script}"
  elif command -v sudo >/dev/null 2>&1; then
    sudo -E bash "${script}"
  else
    die "missing build tools — run: sudo bash ${script}"
  fi
}

# 빌드 deps 스크립트가 있으면 --check-only, 없으면 설치 (SKIP_ENSURE_BUILD_DEPS·DRY_RUN 존중).
ensure_build_deps_script() {
  local deps_script="$1"
  if [ "${DRY_RUN:-0}" -eq 1 ]; then
    log "ensure build dependencies (dry-run: skip)"
    return 0
  fi
  if [ "${SKIP_ENSURE_BUILD_DEPS:-0}" -eq 1 ]; then
    log "SKIP_ENSURE_BUILD_DEPS=1 — skip auto-install"
    return 0
  fi
  if ! bash "${deps_script}" --check-only 2>/dev/null; then
    log "missing build tools — running ${deps_script}"
    run_build_deps_installer "${deps_script}"
  else
    log "build dependencies OK"
  fi
}

# /etc/os-release VERSION_ID 의 major 버전 (8, 9 ...). 판별 불가 시 빈 문자열.
el_major_version() {
  local ver=""
  [ -r /etc/os-release ] && ver="$(. /etc/os-release && printf '%s' "${VERSION_ID:-}")"
  printf '%s' "${ver%%.*}"
}

# EL 배포판 식별자 (Rocky 10 → el10). packaging/<id>, packages/rpm/<id>/ 이름에 사용.
# EL 계열이 아니거나 판별 불가 시 빈 문자열 (Fedora 에서 el42 같은 값이 나오지 않게 한다).
rpm_dist_id() {
  local id="" like="" ver="" major=""
  if [ -r /etc/os-release ]; then
    id="$(. /etc/os-release && printf '%s' "${ID:-}")"
    like="$(. /etc/os-release && printf '%s' "${ID_LIKE:-}")"
    ver="$(. /etc/os-release && printf '%s' "${VERSION_ID:-}")"
  fi
  case " ${id} ${like} " in
    *" rhel "*|*" rocky "*|*" centos "*|*" almalinux "*|*" fedora "*) ;;
    *) return 0 ;;
  esac
  [ "${id}" = "fedora" ] && return 0
  major="${ver%%.*}"
  case "${major}" in
    ''|*[!0-9]*) return 0 ;;
  esac
  printf 'el%s' "${major}"
}

# Ubuntu 배포판 식별자 (24.04 → ubuntu2404). packaging/<id>/debian, packages/deb/<id>/ 이름에 사용. 판별 불가 시 빈 문자열.
ubuntu_dist_id() {
  local ver=""
  [ -r /etc/os-release ] && ver="$(. /etc/os-release && printf '%s' "${VERSION_ID:-}")"
  [ -n "${ver}" ] || return 0
  printf 'ubuntu%s' "${ver//./}"
}

# node major 버전 (없으면 0). 인자: node 바이너리 (기본 PATH 의 node).
node_major_version() {
  local node_bin="${1:-node}" ver
  ver="$("${node_bin}" -v 2>/dev/null || true)"
  ver="${ver#v}"
  ver="${ver%%.*}"
  case "${ver}" in
    ''|*[!0-9]*) printf '0' ;;
    *) printf '%s' "${ver}" ;;
  esac
}

# 산출물 디렉터리를 비운 뒤 재생성 (이전 빌드 잔여물 제거).
prepare_fresh_output_dir() {
  local dir="$1"
  if [ "${DRY_RUN:-0}" -eq 1 ]; then
    log "prepare fresh output: ${dir}/"
    return 0
  fi
  rm -rf "${dir}"
  mkdir -p "${dir}"
}

# java/javac 바이너리의 feature 버전 (판별 불가 시 0).
# 'openjdk version "21.0.12" ...' / 'javac 17.0.20.1' 양쪽 형식 처리.
jdk_major_of() {
  local bin="${1:-java}" ver
  ver="$("${bin}" -version 2>&1 || true)"
  ver="$(printf '%s' "${ver}" | sed -n 's/.*[" ]\([0-9][0-9]*\)[.".].*/\1/p' | head -1)"
  case "${ver}" in
    ''|*[!0-9]*) printf '0' ;;
    *) printf '%s' "${ver}" ;;
  esac
}

# /usr/lib/jvm 에서 JDK(javac 포함) 홈 경로 탐색. 인자: 허용 major 목록 (예: 17, 또는 "17 21").
resolve_jdk_home() {
  local major candidate real_java
  for major in "$@"; do
    for candidate in "/usr/lib/jvm/java-${major}-openjdk" "/usr/lib/jvm/java-${major}-openjdk"-*; do
      if [ -d "${candidate}" ] && [ -x "${candidate}/bin/java" ] && [ -x "${candidate}/bin/javac" ]; then
        printf '%s' "$(readlink -f "${candidate}")"
        return 0
      fi
    done
  done
  # java-<major>-openjdk 이름 규칙을 안 따르는 배포판용 폴백.
  if [ -x /etc/alternatives/java ]; then
    real_java="$(readlink -f /etc/alternatives/java)"
    candidate="$(dirname "$(dirname "${real_java}")")"
    if [ -x "${candidate}/bin/java" ] && [ -x "${candidate}/bin/javac" ]; then
      for major in "$@"; do
        if [ "$(jdk_major_of "${candidate}/bin/java")" = "${major}" ]; then
          printf '%s' "${candidate}"
          return 0
        fi
      done
    fi
  fi
  return 1
}

# EL major 에서 빌드에 쓸 JDK major. Rocky/EL 호스트 전용 (Ubuntu 경로는 verify_jdk 17 고정).
# EL10 부터는 저장소에 java-17-openjdk 가 없어 시스템 JDK 21 을 쓴다.
# NAMUVIRT_JDK_MAJOR 로 강제 가능 (예: /opt 에 직접 설치한 JDK 를 쓸 때).
rocky_jdk_major() {
  local major="${1:-$(el_major_version)}"
  if [ -n "${NAMUVIRT_JDK_MAJOR:-}" ]; then
    printf '%s' "${NAMUVIRT_JDK_MAJOR}"
    return 0
  fi
  case "${major}" in
    ''|*[!0-9]*) printf '17' ;;
    *) if [ "${major}" -ge 10 ]; then printf '21'; else printf '17'; fi ;;
  esac
}

# RPM 이 rpmbuild --short-circuit 산출물인지 확인 (dnf 설치 불가).
rpm_requires_shortcircuited() {
  local rpm_path="$1"
  rpm -qp --requires "${rpm_path}" 2>/dev/null | grep -q 'rpmlib(ShortCircuited)'
}

# runtime RPM 5종 존재·설치 가능 여부 검증.
validate_cloudstack_rpms() {
  local dir="$1" dry_run="$2"
  shift 2
  local pkg rpm_path

  for pkg in "$@"; do
    if [ "${dry_run}" -eq 1 ]; then
      log "require ${dir}/${pkg}-*.rpm"
      continue
    fi
    rpm_path="$(compgen -G "${dir}/${pkg}-*.rpm" | head -1 || true)"
    [ -n "${rpm_path}" ] || die "missing package: ${pkg}-*.rpm in ${dir}"
    if rpm_requires_shortcircuited "${rpm_path}"; then
      die "uninstallable RPM (rpmlib ShortCircuited): ${rpm_path}
  Rebuild with full rpmbuild only (never rpmbuild --short-circuit):
    ./build/rocky.sh"
    fi
  done
}

# 공통 CLI 플래그 파싱 (--mode, --dry-run, --without-vmware 등). --help 시 return 1.
build_parse_common_args() {
  DRY_RUN=0
  MODE="${BUILD_MODE:-normal}"
  WITH_VMWARE=1
  SKIP_ENSURE_BUILD_DEPS=0

  while [ "$#" -gt 0 ]; do
    case "$1" in
      --mode) MODE="$2"; shift 2 ;;
      --without-vmware) WITH_VMWARE=0; shift ;;
      --no-auto-deps) SKIP_ENSURE_BUILD_DEPS=1; shift ;;
      --dry-run) DRY_RUN=1; shift ;;
      -h|--help) return 1 ;;
      *) die "unknown argument: $1" ;;
    esac
  done

  case "${MODE}" in
    normal|dev|clean) ;;
    *) die "invalid mode: ${MODE}" ;;
  esac
}

# BUILD_INFO 메타데이터용 브랜치/커밋 (git 상태로 빌드 차단 안 함).
build_preflight_repo() {
  BRANCH="$(git -C "${REPO_DIR}" rev-parse --abbrev-ref HEAD 2>/dev/null || true)"
  if [ -z "${BRANCH}" ] || [ "${BRANCH}" = "HEAD" ]; then
    BRANCH="$(git -C "${REPO_DIR}" describe --tags --always 2>/dev/null || echo unknown)"
  fi
}

# ~/.m2 에 VMware vim25/pbm JAR 존재 여부.
vmware_maven_jar_exists() {
  local artifact="$1" version="$2"
  [ -s "${HOME}/.m2/repository/com/cloud/com/vmware/${artifact}/${version}/${artifact}-${version}.jar" ]
}

# ~/.m2 에 지정 Maven artifact JAR 존재 여부.
maven_jar_exists() {
  local group_path="$1" artifact="$2" version="$3"
  [ -s "${HOME}/.m2/repository/${group_path}/${artifact}/${version}/${artifact}-${version}.jar" ]
}

# noredist 빌드용 non-OSS JAR — 매 빌드 vendor/install-non-oss.sh 로 ~/.m2 등록.
ensure_vmware_non_oss_deps() {
  [ "${WITH_VMWARE}" -eq 1 ] || return 0
  [ "${DRY_RUN}" -eq 1 ] && return 0

  [ -d "${NON_OSS_DIR}" ] || die "vendor/cloudstack-nonoss not found — JAR 10종이 레포에 있어야 합니다"
  [ -f "${NON_OSS_DIR}/install-non-oss.sh" ] || die "missing ${NON_OSS_DIR}/install-non-oss.sh"
  command -v mvn >/dev/null 2>&1 || die "mvn is required to register non-OSS dependencies"

  (cd "${NON_OSS_DIR}" && sh ./install-non-oss.sh)

  if ! vmware_maven_jar_exists "vmware-vim25" "8.0" || ! vmware_maven_jar_exists "vmware-pbm" "8.0"; then
    die "VMware SDK missing in ~/.m2 after install-non-oss.sh"
  fi
}

# 요구 major 의 java/javac 설치·PATH 확인; 필요 시 JAVA_HOME 자동 설정.
# 인자: 허용 major 목록 (기본 17). Rocky 10 은 21, 그 외/Ubuntu 는 17.
verify_jdk() {
  local majors=("$@") m ok=0 candidate
  [ "${#majors[@]}" -gt 0 ] || majors=(17)
  if [ "${DRY_RUN}" -eq 1 ]; then
    log "verify JDK: java/javac major in [${majors[*]}]"
    return 0
  fi
  # 이미 맞는 JAVA_HOME 이 주어졌으면 그것을 존중 (Docker 이미지의 ENV JAVA_HOME).
  if [ -n "${JAVA_HOME:-}" ] && [ -x "${JAVA_HOME}/bin/javac" ]; then
    for m in "${majors[@]}"; do
      if [ "$(jdk_major_of "${JAVA_HOME}/bin/java")" = "${m}" ]; then
        export PATH="${JAVA_HOME}/bin:${PATH}"
        ok=1
        break
      fi
    done
  fi
  if [ "${ok}" -eq 0 ] && command -v javac >/dev/null 2>&1; then
    for m in "${majors[@]}"; do
      if [ "$(jdk_major_of java)" = "${m}" ] && [ "$(jdk_major_of javac)" = "${m}" ]; then
        ok=1
        break
      fi
    done
  fi
  if [ "${ok}" -eq 0 ] && candidate="$(resolve_jdk_home "${majors[@]}")"; then
    export JAVA_HOME="${candidate}"
    export PATH="${JAVA_HOME}/bin:${PATH}"
    log "JAVA_HOME=${JAVA_HOME}"
    ok=1
  fi
  command -v java >/dev/null 2>&1 || die "java not found — run ./build/rocky.sh or ./build/ubuntu.sh without --no-auto-deps (sudo may be required)"
  command -v javac >/dev/null 2>&1 || die "javac not found — install a JDK (Rocky: deps-rocky.sh, Ubuntu: deps-ubuntu.sh)"
  [ "${ok}" -eq 1 ] \
    || die "JDK major in [${majors[*]}] is required (found java $(jdk_major_of java), javac $(jdk_major_of javac))"
  log "jdk: $(command -v java) major=$(jdk_major_of java)"
}

# cloudstack-management RPM/deb 안에 VMware 모듈·JAR 포함 여부 검증.
verify_vmware_artifacts_in_archive() {
  local archive="$1" format="$2"
  [ "${WITH_VMWARE}" -eq 1 ] || return 0
  if [ "${DRY_RUN}" -eq 1 ]; then
    log "verify VMware artifacts inside cloudstack-management ${format}"
    return 0
  fi

  command -v jar >/dev/null 2>&1 || die "jar command not found; Java JDK is required"
  local verify_dir cloudstack_jar contents

  verify_dir="$(mktemp -d)"
  case "${format}" in
    rpm)
      (cd "${verify_dir}" && rpm2cpio "${archive}" | cpio -idm --quiet)
      cloudstack_jar="$(find "${verify_dir}" -path '*/usr/share/cloudstack-management/lib/cloudstack-*.jar' | sort | tail -1 || true)"
      ;;
    deb)
      dpkg-deb -x "${archive}" "${verify_dir}"
      cloudstack_jar="$(find "${verify_dir}/usr/share/cloudstack-management/lib" -maxdepth 1 -type f -name 'cloudstack-*.jar' | sort | tail -1 || true)"
      ;;
    *) die "unsupported package format: ${format}" ;;
  esac

  [ -n "${cloudstack_jar}" ] || die "cloudstack management jar not found in ${archive}"
  contents="$(jar tf "${cloudstack_jar}" | grep -iE 'META-INF/cloudstack/vmware|com/vmware/vim25|com/vmware/pbm' || true)"
  [ -n "${contents}" ] || die "VMware support was not found inside ${archive}"

  for req in \
    "META-INF/cloudstack/vmware-compute/module.properties" \
    "META-INF/cloudstack/vmware-storage/module.properties" \
    "META-INF/cloudstack/vmware-network/module.properties" \
    "META-INF/cloudstack/vmware-discoverer/module.properties" \
    "com/vmware/vim25/" \
    "com/vmware/pbm/"; do
    grep -qi "${req}" <<<"${contents}" || die "missing VMware artifact: ${req}"
  done
  printf '%s\n' "${contents}" > "${OUT_DIR}/cloudstack-management-vmware-jars.txt"
  rm -rf "${verify_dir}"
}

# SHA256SUMS·BUILD_INFO.txt 작성 (산출물 디렉터리 OUT_DIR).
write_build_metadata() {
  local format="$1" ext="$2"
  if [ "${DRY_RUN}" -eq 1 ]; then
    log "write ${OUT_DIR}/SHA256SUMS"
    log "write ${OUT_DIR}/BUILD_INFO.txt"
    return 0
  fi
  (
    cd "${OUT_DIR}"
    sha256sum ./*."${ext}" > SHA256SUMS
  )
  {
    printf 'build_id=%s\n' "${BUILD_ID}"
    printf 'branch=%s\n' "${BRANCH}"
    printf 'commit=%s\n' "$(git -C "${REPO_DIR}" rev-parse HEAD)"
    printf 'describe=%s\n' "$(git -C "${REPO_DIR}" describe --tags --always --dirty 2>/dev/null || true)"
    printf 'mode=%s\n' "${MODE}"
    printf 'with_vmware=%s\n' "${WITH_VMWARE}"
    printf 'package_format=%s\n' "${format}"
    [ -n "${RPM_DIST:-}" ] && printf 'rpm_dist=%s\n' "${RPM_DIST}"
    [ -n "${DEB_DIST:-}" ] && printf 'deb_dist=%s\n' "${DEB_DIST}"
    [ -n "${DEBIAN_SRC_DIR:-}" ] && printf 'debian_dir=%s\n' "${DEBIAN_SRC_DIR#"${REPO_DIR}/"}"
    printf 'build_os=%s\n' "$( [ -r /etc/os-release ] && . /etc/os-release && printf '%s' "${PRETTY_NAME:-unknown}" || printf unknown)"
    printf 'repo_dir=%s\n' "${REPO_DIR}"
    printf 'built_at=%s\n' "$(date -Is)"
  } > "${OUT_DIR}/BUILD_INFO.txt"
}
