# namuVIRT 패키지 빌드

이 레포지토리에서 CloudStack 패키지를 빌드합니다. non-OSS JAR는 `vendor/cloudstack-nonoss/`에 **커밋**되어 있습니다.

## 빠른 시작

```bash
# Rocky 8 / 9 / 10 — RPM (호스트 OS 로 el8/el9/el10 자동 선택, 빌드 도구 없으면 자동 설치, sudo 사용 가능)
./build/rocky.sh

# Ubuntu 24.04 / 26.04 — deb (호스트 OS 로 ubuntu2404/ubuntu2604 자동 선택, 빌드 도구 없으면 자동 설치, sudo 사용 가능)
./build/ubuntu.sh
```

**동작:** 호스트 deps 없으면 설치 → 소스 풀 빌드 → `build/packages/*/latest/`에 산출. git 상태·이전 산출물 재사용으로 빌드를 건너뛰지 않음.

산출물:

| 스크립트 | 패키지 경로 |
|----------|-------------|
| `./build/rocky.sh` (Rocky 8) | `build/packages/rpm/el8/latest/*.rpm` |
| `./build/rocky.sh` (Rocky 9) | `build/packages/rpm/el9/latest/*.rpm` |
| `./build/rocky.sh` (Rocky 10) | `build/packages/rpm/el10/latest/*.rpm` |
| `./build/ubuntu.sh` (Ubuntu 24.04) | `build/packages/deb/ubuntu2404/latest/*.deb` |
| `./build/ubuntu.sh` (Ubuntu 26.04) | `build/packages/deb/ubuntu2604/latest/*.deb` |

매 빌드마다 `SHA256SUMS`, `BUILD_INFO.txt`가 생성됩니다 (브랜치·커밋은 메타데이터에만 기록, 경로에는 없음).

## 공통 옵션

| 플래그 | 설명 |
|--------|------|
| `--mode normal\|dev\|clean` | `normal`/`dev`: 테스트 스킵; `clean`: `mvn clean` 포함 |
| `--without-vmware` | OSS만 빌드 (noredist 생략) |
| `--dry-run` | 실행 계획만 출력 |
| `--no-auto-deps` | deps 자동 설치 생략 |

## 빌드 의존성 (자동 설치)

| OS | 스크립트 | 설치 내용 |
|----|----------|-----------|
| Rocky 8 | `build/lib/deps-rocky.sh` | Java 17, rpmbuild, Node 18 (`nodejs:18` 모듈), genisoimage, Maven `/opt/maven` |
| Rocky 9 | `build/lib/deps-rocky.sh` | Java 17, rpmbuild, Node 20 (`nodejs:20` 모듈), xorriso, Maven `/opt/maven` |
| Rocky 10 | `build/lib/deps-rocky.sh` | **JDK 21**, rpmbuild, Node 22 (기본 스트림 — dnf modularity 없음), xorriso, Maven `/opt/maven` |
| Ubuntu 24.04 | `build/lib/deps-ubuntu.sh` | openjdk-17-jdk, maven, devscripts, Node 18, python2 equivs 등 |
| Ubuntu 26.04 | `build/lib/deps-ubuntu.sh` | openjdk-17-jdk, maven, devscripts, Node 22, python2 equivs 등 |

빌드 스크립트가 누락 시 자동 호출합니다. 일반 사용자로 실행하면 `sudo`로 deps 설치를 시도합니다.

수동 확인:

```bash
sudo ./build/lib/deps-rocky.sh --check-only
sudo ./build/lib/deps-ubuntu.sh --check-only
```

## RPM packaging 디렉터리 (OS별)

`packaging/<dist>/cloud.spec` 을 그대로 사용합니다. 없는 dist 로 빌드하면 시작 전에 중단됩니다.

| 빌드 호스트 | 사용하는 packaging |
|-------------|--------------------|
| Rocky 8 | `packaging/el8/` |
| Rocky 9 | `packaging/el8/` (`packaging/el9` 는 심볼릭 링크) |
| Rocky 10 | `packaging/el10/` (실제 디렉터리) |
| centos8 / suse15 | `packaging/el8/` (심볼릭 링크) |

- dist 이름은 `el` + `/etc/os-release` 의 `VERSION_ID` major. `RPM_DIST` 로 덮어쓸 수 있습니다.
- `packaging/el10` 은 el8 사본이지만 **별도 파일**입니다. upstream `cloud.spec` 변경을 머지할 때 양쪽을 함께 갱신해야 합니다 — `packaging/README.md` 참고.
- 두 spec 의 데이터 파일 경로는 `%global cspkgdir` 매크로로 갈립니다. 그래서 `diff packaging/el8/cloud.spec packaging/el10/cloud.spec` 는 그 한 줄만 달라야 합니다.

## Rocky 10 (el10) 주의사항

- Rocky 10 저장소에는 `java-17-openjdk` 가 없습니다 (21, 25만. EPEL 10 에도 없음). 그래서 **시스템 JDK 21** 로 빌드합니다. `pom.xml` 의 `cs.jdk.version=11` 이라 바이트코드 타깃은 그대로이고, RPM 의 `Requires: (java-17-openjdk or java-21-openjdk)` 는 21 로 충족됩니다. `NAMUVIRT_JDK_MAJOR` 로 강제할 수 있습니다.
- `dnf module` 이 제거돼 nodejs 모듈 스트림 전환을 하지 않습니다. 기본 nodejs 22 를 그대로 씁니다.
- `cloudstack-baremetal-agent` 는 el10 에서 **설치할 수 없습니다** (`dhcp`, `xinetd` 가 저장소에 없음). 빌드는 정상이고 runtime 5종(common/management/agent/ui/usage)은 영향이 없습니다.

## Ubuntu debian 디렉터리 (OS별)

`dpkg-buildpackage` 는 루트 `debian/` 만 읽으므로, `./build/ubuntu.sh` 가 빌드 동안 OS별 디렉터리를 `debian/` 에 임시로 교체하고 끝나면 (실패·중단 포함) 원복합니다.

| 빌드 호스트 | 사용하는 debian |
|-------------|-----------------|
| Ubuntu 24.04 | `packaging/ubuntu2404/debian/` |
| Ubuntu 26.04 | `packaging/ubuntu2604/debian/` |
| 그 외 | 루트 `debian/` (경고 출력) |

- 이름 규칙: `ubuntu` + `/etc/os-release` 의 `VERSION_ID` 에서 점 제거. `DEB_DIST` 환경변수로 덮어쓸 수 있습니다.
- changelog 도 OS별로 따로 있습니다. 빌드 시 사용할 changelog 의 첫 버전이 `pom.xml` 버전과 다르면 중단합니다.
  `tools/build/setnextversion.sh` 는 루트와 `packaging/ubuntu*/debian/changelog` 를 함께 올립니다.
- OS 한쪽만 바꿀 변경(Depends 등)은 해당 `packaging/ubuntuXXXX/debian/` 에만 반영합니다.

## Docker 빌더

```bash
# Rocky 8 / 9 / 10
docker build -f build/docker/Dockerfile --build-arg ROCKY_VERSION=10 -t namuvirt-build-rocky10 build/
docker run --rm -v "$PWD":/src:ro -v "$PWD/build/packages/rpm":/out namuvirt-build-rocky10

# Ubuntu 24.04 / 26.04
docker build -f build/docker/Dockerfile.ubuntu --build-arg UBUNTU_VERSION=26.04 -t namuvirt-build-ubuntu2604 build/
docker run --rm -v "$PWD":/src:ro -v "$PWD/build/packages/deb":/out namuvirt-build-ubuntu2604
```

엔트리포인트(`build/docker/entrypoint.sh`)는 컨테이너 OS 를 보고 `build/rocky.sh` 또는 `build/ubuntu.sh` 를 실행합니다.
Windows 작업트리를 그대로 마운트하면 두 가지가 깨집니다: CRLF 때문에 셸 스크립트가 실패하고, `core.symlinks=false` 때문에 `packaging/el9` 등이 `el8` 이라는 3바이트 텍스트 파일이 됩니다. LF·심볼릭 링크 체크아웃을 쓰거나, 컨테이너 안에서 clone 하세요.

```bash
docker run --rm -v "$PWD":/repo:ro -v "$PWD/build/packages/rpm":/out   --entrypoint bash namuvirt-build-rocky10 -lc '
    git config --global --add safe.directory "*"
    git clone --no-hardlinks --branch <브랜치> /repo /src
    SRC_DIR=/src OUT_DIR=/out /usr/local/bin/namuvirt-build-entrypoint
  '
```

## non-OSS 모듈

`vendor/cloudstack-nonoss/README.md` 참고. noredist 빌드 전 JAR 10종이 모두 있어야 합니다.

## 디렉터리 구조

```text
build/
  rocky.sh          ubuntu.sh     ← 엔트리
  lib/              common, rocky, ubuntu, deps-rocky, deps-ubuntu
  docker/           Dockerfile (Rocky 8/9/10), Dockerfile.ubuntu (Ubuntu 24.04/26.04), entrypoint.sh
  packages/rpm/el8/latest/
  packages/rpm/el9/latest/
  packages/rpm/el10/latest/
  packages/deb/ubuntu2404/latest/
  packages/deb/ubuntu2604/latest/
packaging/el8/  packaging/el10/               ← OS별 RPM spec
packaging/ubuntu2404/debian/  packaging/ubuntu2604/debian/   ← OS별 debian
vendor/cloudstack-nonoss/   ← JAR + install-non-oss.sh
```

`git checkout`, `git reset`, `git clean`은 **실행하지 않습니다**.
