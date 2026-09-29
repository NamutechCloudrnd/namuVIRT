# Rocky 8/9/10 RPM 빌더 이미지. 빌드 컨텍스트는 build/ 디렉터리.
#   docker build -f build/docker/Dockerfile -t namuvirt-build-rocky8 build/
#   docker build -f build/docker/Dockerfile --build-arg ROCKY_VERSION=9 -t namuvirt-build-rocky9 build/
#   docker build -f build/docker/Dockerfile --build-arg ROCKY_VERSION=10 -t namuvirt-build-rocky10 build/
# 실행: 레포를 /src 에 마운트, 산출물은 /out/<el8|el9|el10>/latest/
#   docker run --rm -v "$PWD":/src:ro -v "$PWD/build/packages/rpm":/out namuvirt-build-rocky10
# 빌드 의존성은 build/lib/deps-rocky.sh 로 이미지에 미리 굽는다.
ARG ROCKY_VERSION=8.10
FROM rockylinux/rockylinux:${ROCKY_VERSION}

RUN dnf -y install git rsync tar findutils diffutils procps-ng ca-certificates \
  && dnf clean all

# 빌드 도구(JDK, rpmbuild, Node, Maven /opt/maven) 설치. JDK 는 deps-rocky.sh 가
# OS 버전별로 선택 (Rocky 8/9: 17, Rocky 10: 21 — 저장소에 17 이 없음).
# nodejs 모듈 스트림도 OS 버전별 (Rocky 8: 18, Rocky 9: 20, Rocky 10: modularity 없음 → 기본).
# 비우면 기본값.
ARG NODEJS_STREAM=
COPY lib/ /opt/namuvirt-build/lib/
RUN NAMUVIRT_BUILD_DIR=/opt/namuvirt-build \
    NAMUVIRT_REPO_ROOT=/opt/namuvirt-build \
    NODEJS_STREAM="${NODEJS_STREAM}" \
    bash /opt/namuvirt-build/lib/deps-rocky.sh \
  && dnf clean all

COPY docker/entrypoint.sh /usr/local/bin/namuvirt-build-entrypoint
RUN chmod 755 /usr/local/bin/namuvirt-build-entrypoint

# JDK 경로는 OS 버전마다 다르므로(java-17-openjdk / java-21-openjdk) 버전 무관
# 심볼릭 링크를 만들어 ENV 에서 쓴다. javac 로 이미지 빌드 시점에 검증한다.
RUN . /etc/profile.d/namuvirt-java.sh \
  && ln -sfn "${JAVA_HOME}" /opt/namuvirt-jdk \
  && /opt/namuvirt-jdk/bin/javac -version

ENV JAVA_HOME=/opt/namuvirt-jdk \
    PATH=/opt/namuvirt-jdk/bin:/opt/maven/bin:/usr/bin:/bin:/usr/sbin:/sbin:/usr/local/bin \
    SRC_DIR=/src \
    WORK_DIR=/work \
    OUT_DIR=/out

WORKDIR /work
ENTRYPOINT ["/usr/local/bin/namuvirt-build-entrypoint"]
