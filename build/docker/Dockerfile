# Rocky 8/9 RPM 빌더 이미지. 빌드 컨텍스트는 build/ 디렉터리.
#   docker build -f build/docker/Dockerfile -t namuvirt-build-rocky8 build/
#   docker build -f build/docker/Dockerfile --build-arg ROCKY_VERSION=9 -t namuvirt-build-rocky9 build/
# 실행: 레포를 /src 에 마운트, 산출물은 /out/<el8|el9>/latest/
#   docker run --rm -v "$PWD":/src:ro -v "$PWD/build/packages/rpm":/out namuvirt-build-rocky9
# 빌드 의존성은 build/lib/deps-rocky.sh 로 이미지에 미리 굽는다.
ARG ROCKY_VERSION=8.10
FROM rockylinux/rockylinux:${ROCKY_VERSION}

RUN dnf -y install git rsync tar findutils diffutils procps-ng ca-certificates \
  && dnf clean all

# 빌드 도구(Java 17, rpmbuild, Node, Maven /opt/maven) 설치.
# nodejs 모듈 스트림은 deps-rocky.sh 가 OS 버전별로 선택 (Rocky 8: 18, Rocky 9: 20). 비우면 기본값.
ARG NODEJS_STREAM=
COPY lib/ /opt/namuvirt-build/lib/
RUN NAMUVIRT_BUILD_DIR=/opt/namuvirt-build \
    NAMUVIRT_REPO_ROOT=/opt/namuvirt-build \
    NODEJS_STREAM="${NODEJS_STREAM}" \
    bash /opt/namuvirt-build/lib/deps-rocky.sh \
  && dnf clean all

COPY docker/entrypoint.sh /usr/local/bin/namuvirt-build-entrypoint
RUN chmod 755 /usr/local/bin/namuvirt-build-entrypoint

ENV JAVA_HOME=/usr/lib/jvm/java-17-openjdk \
    PATH=/opt/maven/bin:/usr/bin:/bin:/usr/sbin:/sbin:/usr/local/bin \
    SRC_DIR=/src \
    WORK_DIR=/work \
    OUT_DIR=/out

WORKDIR /work
ENTRYPOINT ["/usr/local/bin/namuvirt-build-entrypoint"]
