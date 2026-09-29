#!/usr/bin/env bash
# Rocky 8/9/10 빌드 호스트 의존성 설치·검사.
# ./build/rocky.sh 가 자동 호출하거나, 수동: sudo ./build/lib/deps-rocky.sh

set -Eeuo pipefail

export NAMUVIRT_SCRIPT_TAG="${NAMUVIRT_SCRIPT_TAG:-build/deps-rocky}"
LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUILD_DIR="${NAMUVIRT_BUILD_DIR:-$(cd "${LIB_DIR}/.." && pwd)}"
export NAMUVIRT_BUILD_DIR="${BUILD_DIR}"
export NAMUVIRT_REPO_ROOT="${NAMUVIRT_REPO_ROOT:-$(cd "${BUILD_DIR}/.." && pwd)}"

# shellcheck disable=SC1091
source "${LIB_DIR}/common.sh"

MAVEN_VERSION="${MAVEN_VERSION:-3.9.16}"
MAVEN_INSTALL_DIR="${MAVEN_INSTALL_DIR:-/opt/apache-maven-${MAVEN_VERSION}}"
MAVEN_LINK="${MAVEN_LINK:-/opt/maven}"

# UI(webpack 4) 빌드용 Node 최소 major. Rocky 9 기본 nodejs 는 16 이라 모듈 스트림 전환 필요.
NODE_MIN_MAJOR="${NODE_MIN_MAJOR:-18}"
EL_MAJOR="$(el_major_version)"
# set -u 아래에서 [ "" -ge 9 ] 가 죽지 않도록 숫자 비교용 변수를 따로 둔다.
case "${EL_MAJOR}" in
  ''|*[!0-9]*) EL_MAJOR_NUM=0 ;;
  *) EL_MAJOR_NUM="${EL_MAJOR}" ;;
esac
# 빌드에 쓸 JDK major (EL8/EL9: 17, EL10+: 21 — 저장소에 java-17-openjdk 가 없음).
JDK_MAJOR="$(rocky_jdk_major "${EL_MAJOR}")"
if [ "${EL_MAJOR_NUM}" -ge 10 ]; then
  # EL10 은 dnf modularity 가 제거됐고 기본 nodejs 가 22 라 스트림 전환이 불필요·불가능.
  NODEJS_STREAM="${NODEJS_STREAM:-none}"
elif [ "${EL_MAJOR_NUM}" -eq 9 ]; then
  NODEJS_STREAM="${NODEJS_STREAM:-20}"
else
  NODEJS_STREAM="${NODEJS_STREAM:-18}"
fi

# --help 출력.
usage() {
  cat <<USAGE
Usage:
  ./build/lib/deps-rocky.sh [--check-only] [--dry-run]

Installs Rocky 8/9/10 build tools for ./build/rocky.sh:
  JDK ${JDK_MAJOR}, rpm-build, nodejs:${NODEJS_STREAM} (>= ${NODE_MIN_MAJOR}), Maven ${MAVEN_VERSION} -> ${MAVEN_LINK}
USAGE
}

# Apache Maven tarball 다운로드 URL.
maven_download_url() {
  printf '%s' "https://dlcdn.apache.org/maven/maven-3/${1}/binaries/apache-maven-${1}-bin.tar.gz"
}

# Maven tarball 다운로드 (dlcdn 실패 시 archive.apache.org).
fetch_maven_archive() {
  local version="$1" dest="$2" primary fallback
  primary="$(maven_download_url "${version}")"
  fallback="https://archive.apache.org/dist/maven/maven-3/${version}/binaries/apache-maven-${version}-bin.tar.gz"
  log "download ${primary}"
  if curl -fsSL -o "${dest}" "${primary}"; then
    return 0
  fi
  warn "primary Maven mirror failed; trying archive.apache.org"
  log "download ${fallback}"
  curl -fsSL -o "${dest}" "${fallback}"
}

# /opt/maven 을 PATH 앞에 추가.
build_deps_path() {
  if [ -x "${MAVEN_LINK}/bin/mvn" ]; then
    export PATH="${MAVEN_LINK}/bin:${PATH}"
  fi
}

# 누락된 빌드 도구를 stdout 에 한 줄씩 출력. 모두 있으면 exit 0.
build_deps_missing() {
  build_deps_path
  local ok_java=1 ok_tools=1

  if [ "$(jdk_major_of java)" = "${JDK_MAJOR}" ] \
    && command -v javac >/dev/null 2>&1 \
    && [ "$(jdk_major_of javac)" = "${JDK_MAJOR}" ]; then
    :
  elif resolve_jdk_home "${JDK_MAJOR}" >/dev/null 2>&1; then
    :
  else
    ok_java=0
    printf '%s\n' "java-${JDK_MAJOR}-openjdk-devel (java/javac ${JDK_MAJOR})"
  fi

  for tool in rpmbuild rpm2cpio cpio mvn node npm python3 make g++ jq curl wget; do
    command -v "${tool}" >/dev/null 2>&1 || {
      ok_tools=0
      printf '%s\n' "${tool}"
    }
  done

  if command -v node >/dev/null 2>&1 && [ "$(node_major_version)" -lt "${NODE_MIN_MAJOR}" ]; then
    ok_tools=0
    printf '%s\n' "nodejs>=${NODE_MIN_MAJOR} (found $(node -v 2>/dev/null))"
  fi

  if command -v mvn >/dev/null 2>&1; then
    local mvn_ver min_ok
    mvn_ver="$(mvn -version 2>/dev/null | awk '/Apache Maven/{print $3; exit}')"
    if [ -z "${mvn_ver}" ]; then
      ok_tools=0
      printf '%s\n' 'mvn (version parse failed)'
    else
      min_ok="$(printf '%s\n' '3.6.3' "${mvn_ver}" | sort -V | head -1)"
      if [ "${min_ok}" != "3.6.3" ]; then
        ok_tools=0
        printf '%s\n' "maven>=3.6.3 (found ${mvn_ver})"
      fi
    fi
  fi

  [ "${ok_java}" -eq 1 ] && [ "${ok_tools}" -eq 1 ]
}

# dnf 로 java-<JDK_MAJOR>-openjdk-devel 설치.
install_jdk_devel() {
  if [ "${DRY_RUN}" -eq 1 ]; then
    log "dnf install -y java-${JDK_MAJOR}-openjdk-devel"
    return 0
  fi
  if rpm -q "java-${JDK_MAJOR}-openjdk-devel" >/dev/null 2>&1; then
    log "java-${JDK_MAJOR}-openjdk-devel already installed"
    return 0
  fi
  run dnf install -y "java-${JDK_MAJOR}-openjdk-devel"
}

# 존재하는 alternatives 패밀리만 --set (EL10 에는 java_sdk_<major> 계열이 없다).
alternatives_set_if_present() {
  local family="$1" target="$2"
  if alternatives --display "${family}" >/dev/null 2>&1; then
    run alternatives --set "${family}" "${target}"
  else
    log "alternatives family ${family} not present — skip"
  fi
}

# alternatives 로 시스템 기본 java/javac 을 JDK_MAJOR 로 설정.
configure_jdk_alternatives() {
  local java_home
  if [ "${DRY_RUN}" -eq 1 ]; then
    log "alternatives --set java/javac to JDK ${JDK_MAJOR}"
    return 0
  fi
  java_home="$(resolve_jdk_home "${JDK_MAJOR}")" \
    || die "JDK ${JDK_MAJOR} not found under /usr/lib/jvm after install"
  alternatives_set_if_present "java_sdk_${JDK_MAJOR}_openjdk" "${java_home}"
  alternatives_set_if_present "java_sdk_${JDK_MAJOR}" "${java_home}"
  alternatives_set_if_present java "${java_home}/bin/java"
  alternatives_set_if_present javac "${java_home}/bin/javac"
  [ "$(jdk_major_of java)" = "${JDK_MAJOR}" ] || die "system java is not ${JDK_MAJOR} after alternatives"
  [ "$(jdk_major_of javac)" = "${JDK_MAJOR}" ] || die "system javac is not ${JDK_MAJOR} after alternatives"
  log "alternatives: java/javac -> ${java_home}"
}

# /etc/profile.d/namuvirt-java.sh 에 JAVA_HOME 기록.
write_java_home_profile() {
  local java_home
  if [ "${DRY_RUN}" -eq 1 ]; then
    log "write /etc/profile.d/namuvirt-java.sh"
    return 0
  fi
  java_home="$(resolve_jdk_home "${JDK_MAJOR}")" || die "JDK ${JDK_MAJOR} not found for profile.d"
  # 이전 버전이 남긴 파일 제거 (JAVA_HOME 이 두 번 export 되는 것을 막는다).
  rm -f /etc/profile.d/namuvirt-java17.sh
  cat > /etc/profile.d/namuvirt-java.sh <<EOF
# namuVIRT Rocky build host — JDK ${JDK_MAJOR}
export JAVA_HOME=${java_home}
export PATH=\${JAVA_HOME}/bin:\${PATH}
EOF
  chmod 644 /etc/profile.d/namuvirt-java.sh
}

# nodejs 모듈 스트림을 NODEJS_STREAM 으로 전환 (설치된 node 가 NODE_MIN_MAJOR 미만일 때).
install_nodejs_stream() {
  if [ "${NODEJS_STREAM}" = "none" ]; then
    # EL10+ 는 dnf modularity 가 제거돼 module reset/enable 이 실패한다. 기본 nodejs(22)로 충분.
    log "EL${EL_MAJOR}: dnf modularity unavailable — using the default nodejs stream"
    return 0
  fi
  if [ "${DRY_RUN}" -eq 1 ]; then
    log "dnf module enable nodejs:${NODEJS_STREAM} (if node < ${NODE_MIN_MAJOR})"
    return 0
  fi
  if [ "$(node_major_version)" -ge "${NODE_MIN_MAJOR}" ]; then
    log "nodejs $(node -v) already >= ${NODE_MIN_MAJOR}"
    return 0
  fi
  run dnf -y module reset nodejs
  run dnf -y module enable "nodejs:${NODEJS_STREAM}"
  local installed=() pkg
  for pkg in nodejs npm; do
    rpm -q "${pkg}" >/dev/null 2>&1 && installed+=("${pkg}")
  done
  if [ "${#installed[@]}" -gt 0 ]; then
    run dnf -y distro-sync "${installed[@]}"
  fi
}

# dnf 로 rpmbuild·nodejs·gcc 등 RPM/UI 빌드 패키지 설치.
install_build_packages() {
  # EL9+ 기본 저장소에는 genisoimage 가 없음 — xorriso 가 /usr/bin/mkisofs 를 제공해
  # cloud.spec 의 `BuildRequires: /usr/bin/mkisofs` 를 충족한다.
  local iso_pkg=genisoimage
  [ "${EL_MAJOR_NUM}" -ge 9 ] && iso_pkg=xorriso
  # cpio: common.sh 의 verify_vmware_artifacts_in_archive 가 rpm2cpio 와 함께 사용.
  # systemd-rpm-macros: cloud.spec 의 %{_unitdir} 전개에 필요 (기본 이미지에 없음).
  # /usr/bin/curl: 패키지명 'curl' 을 쓰면 Rocky 9/10 기본 이미지의 curl-minimal 과
  #   충돌해 dnf 트랜잭션 전체가 실패한다. 파일 provide 는 양쪽 모두 충족한다.
  local pkgs=(
    rpm-build rpm-sign systemd-rpm-macros nodejs npm python3 python3-setuptools
    make gcc gcc-c++ glibc-devel "${iso_pkg}" jpackage-utils
    wget /usr/bin/curl tar patch which jq cpio
  )
  if [ "${DRY_RUN}" -eq 1 ]; then
    log "dnf install -y ${pkgs[*]}"
    return 0
  fi
  run dnf install -y "${pkgs[@]}"
}

# Apache Maven 을 /opt/maven 에 설치 (Rocky appstream 3.5.x 대신).
install_maven() {
  if [ "${DRY_RUN}" -eq 1 ]; then
    log "install Apache Maven ${MAVEN_VERSION} -> ${MAVEN_LINK}"
    return 0
  fi
  if [ -x "${MAVEN_LINK}/bin/mvn" ]; then
    local mvn_ver min_ok
    mvn_ver="$("${MAVEN_LINK}/bin/mvn" -version 2>/dev/null | awk '/Apache Maven/{print $3; exit}')"
    if [ -n "${mvn_ver}" ]; then
      min_ok="$(printf '%s\n' '3.6.3' "${mvn_ver}" | sort -V | head -1)"
      if [ "${min_ok}" = "3.6.3" ]; then
        log "Maven ${mvn_ver} already at ${MAVEN_LINK}"
        return 0
      fi
    fi
  fi
  local archive tmpdir
  tmpdir="$(mktemp -d)"
  archive="${tmpdir}/apache-maven-${MAVEN_VERSION}-bin.tar.gz"
  fetch_maven_archive "${MAVEN_VERSION}" "${archive}"
  run tar -xzf "${archive}" -C /opt
  [ -d "${MAVEN_INSTALL_DIR}" ] || die "Maven extract dir missing: ${MAVEN_INSTALL_DIR}"
  ln -sfn "${MAVEN_INSTALL_DIR}" "${MAVEN_LINK}"
  rm -rf "${tmpdir}"
  log "Maven ${MAVEN_VERSION} -> ${MAVEN_LINK}"
}

# /etc/profile.d/namuvirt-maven.sh 에 Maven PATH 기록.
write_maven_profile() {
  if [ "${DRY_RUN}" -eq 1 ]; then
    log "write /etc/profile.d/namuvirt-maven.sh"
    return 0
  fi
  cat > /etc/profile.d/namuvirt-maven.sh <<EOF
# namuVIRT Rocky build host — Apache Maven
export PATH=${MAVEN_LINK}/bin:\${PATH}
EOF
  chmod 644 /etc/profile.d/namuvirt-maven.sh
}

# ── CLI ───────────────────────────────────────────────────────────

CHECK_ONLY=0
DRY_RUN=0

while [ "$#" -gt 0 ]; do
  case "$1" in
    --check-only) CHECK_ONLY=1; shift ;;
    --dry-run) DRY_RUN=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) die "unknown argument: $1" ;;
  esac
done

require_root

if [ "${DRY_RUN}" -eq 1 ]; then
  log "check build dependencies (dry-run)"
  if build_deps_missing >/tmp/namuvirt-build-deps-missing.$$ 2>/dev/null; then
    log "all build dependencies present"
  else
    log "would install missing:"
    sed 's/^/  - /' /tmp/namuvirt-build-deps-missing.$$
    log "would run full deps-rocky install"
  fi
  rm -f /tmp/namuvirt-build-deps-missing.$$
  exit 0
fi

if build_deps_missing >/tmp/namuvirt-build-deps-missing.$$ 2>/dev/null; then
  rm -f /tmp/namuvirt-build-deps-missing.$$
  log "build dependencies OK"
  exit 0
fi

log "missing build dependencies:"
sed 's/^/  - /' /tmp/namuvirt-build-deps-missing.$$
rm -f /tmp/namuvirt-build-deps-missing.$$

if [ "${CHECK_ONLY}" -eq 1 ]; then
  exit 1
fi

install_jdk_devel
configure_jdk_alternatives
write_java_home_profile
install_nodejs_stream
install_build_packages
install_maven
write_maven_profile
build_deps_path
build_deps_missing >/dev/null 2>&1 || die "build dependencies still missing after install"

log "done — build dependencies ready"
