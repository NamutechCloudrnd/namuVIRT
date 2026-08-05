# Rocky 8.10 RPM 빌더 이미지. 빌드 컨텍스트는 build/ 디렉터리.
#   docker build -f build/docker/Dockerfile -t namuvirt-build-rocky8 build/
# 빌드 의존성은 build/lib/deps-rocky.sh 로 이미지에 미리 굽는다.
FROM rockylinux/rockylinux:8.10

# Rocky 8 기본 nodejs 모듈 스트림은 10 — CloudStack UI 빌드에 너무 낮다.
# deps-rocky.sh 의 `dnf install nodejs` 보다 먼저 스트림을 올려 둔다.
ARG NODEJS_STREAM=18
RUN dnf -y module reset nodejs \
  && dnf -y module enable "nodejs:${NODEJS_STREAM}" \
  && dnf -y install git rsync tar findutils diffutils procps-ng ca-certificates \
  && dnf clean all

# 빌드 도구(Java 17, rpmbuild, Node, Maven /opt/maven) 설치.
COPY lib/ /opt/namuvirt-build/lib/
RUN NAMUVIRT_BUILD_DIR=/opt/namuvirt-build \
    NAMUVIRT_REPO_ROOT=/opt/namuvirt-build \
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