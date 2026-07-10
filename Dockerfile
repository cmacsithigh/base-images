# Stage 1: Build the Single-File Binaries
FROM oven/bun:1.3 AS builder

ARG NEWMAN_VERSION=6.2.2

WORKDIR /build

# 1. Install Node.js & pkg (Needed because Bun can't bundle Newman's dynamic deps)
RUN apt-get update && apt-get install -y nodejs npm

# 3. Build Newman with Vercel pkg (Standalone ELF)
# pkg handles the dynamic dependencies that Bun's compiler missed
RUN npm install -g pkg && \
    npm install newman@${NEWMAN_VERSION} && \
    pkg ./node_modules/newman/bin/newman.js --targets node18-linux-x64 --output newman_bin

# Stage 2: Binary Fetcher (Static Go-based tools & Scripts)
FROM fedora:44 AS binfetch
RUN dnf -y install ca-certificates curl tar gzip && dnf clean all

ARG ARGOCD_VERSION=v3.3.8
RUN curl -fsSL -o /usr/local/bin/argocd "https://github.com/argoproj/argo-cd/releases/download/${ARGOCD_VERSION}/argocd-linux-amd64" && \
    chmod +x /usr/local/bin/argocd

ARG KIND_VERSION=v0.27.0
RUN curl -fsSL -o /usr/local/bin/kind "https://github.com/kubernetes-sigs/kind/releases/download/${KIND_VERSION}/kind-linux-amd64" && \
    chmod +x /usr/local/bin/kind

ARG KUSTOMIZE_VERSION=v5.8.1
RUN curl -fsSL "https://raw.githubusercontent.com/kubernetes-sigs/kustomize/master/hack/install_kustomize.sh" | bash -s -- "${KUSTOMIZE_VERSION#v}" && \
    mv kustomize /usr/local/bin/kustomize && \
    chmod +x /usr/local/bin/kustomize

RUN curl -fsSL -o /usr/local/bin/blackduck https://detect.blackduck.com/detect.sh && \
    chmod +x /usr/local/bin/blackduck

# Roxctl download consolidated into the binary fetching phase
ARG ROXCTL_VERSION=4.4.0
RUN curl -fsSL -o /usr/local/bin/roxctl \
    "https://mirror.openshift.com/pub/rhacs/assets/${ROXCTL_VERSION}/bin/Linux/roxctl" && \
    chmod +x /usr/local/bin/roxctl

# FIXED: Fetch and extract official OpenJDK 17 inside the binfetcher stage
RUN mkdir -p /usr/lib/jvm/openjdk-17 && \
    curl -fsSL "https://download.java.net/java/GA/jdk17.0.2/dfd4a8d0985749f896bed50d7138ee7f/8/GPL/openjdk-17.0.2_linux-x64_bin.tar.gz" | \
    tar -xzf - --strip-components=1 -C /usr/lib/jvm/openjdk-17

# Stage 3: Final Production Image
FROM fedora:44

# Essential runtime libs only
RUN dnf -y install --setopt=install_weak_deps=False \
    ca-certificates bash git curl podman buildah shadow-utils shadow-utils-subid libstdc++ libatomic \
    && dnf clean all && rm -rf /var/cache/dnf

# 1. Copy Docker/K8s/Helm from official static images
COPY --from=docker.io/library/docker:26-cli /usr/local/bin/docker /usr/local/bin/docker
COPY --from=registry.k8s.io/kubectl:v1.32.0 /bin/kubectl /usr/local/bin/kubectl
COPY --from=docker.io/alpine/helm:4.2.2 /usr/bin/helm /usr/local/bin/helm
COPY --from=docker.io/stackrox/kube-linter:v0.8.3 /kube-linter /usr/local/bin/kube-linter
COPY --from=quay.io/openshift/origin-cli:4.20 /usr/bin/oc /usr/local/bin/oc
COPY --from=quay.io/skopeo/stable:v1.16 /usr/bin/skopeo /usr/local/bin/skopeo

# 2. Copy tools from binfetch (Includes Black Duck and Roxctl)
COPY --from=binfetch /usr/local/bin/argocd /usr/local/bin/argocd
COPY --from=binfetch /usr/local/bin/kind /usr/local/bin/kind
COPY --from=binfetch /usr/local/bin/kustomize /usr/local/bin/kustomize
COPY --from=binfetch /usr/local/bin/blackduck /usr/local/bin/blackduck
COPY --from=binfetch /usr/local/bin/roxctl /usr/local/bin/roxctl

# FIXED: Copy the standalone OpenJDK binaries from Stage 2
COPY --from=binfetch /usr/lib/jvm/openjdk-17 /usr/lib/jvm/openjdk-17

# 3. Copy our "Truly Single" Binaries
COPY --from=builder /build/newman_bin /usr/local/bin/newman

ARG BRUNO_VERSION=3.3.0
ARG MAVEN_VERSION=3.9.9

# Install remaining package-based utilities
RUN dnf -y install --setopt=install_weak_deps=False \
    nodejs npm curl jq yq \
    maven \
    && dnf clean all && rm -rf /var/cache/dnf

# Install Bruno CLI
RUN npm config set update-notifier false && \
    npm config set fund false && \
    npm config set audit false && \
    npm install -g --prefix /usr/local @usebruno/cli@${BRUNO_VERSION} && \
    npm cache clean --force

RUN npm install \
      semantic-release \
      conventional-changelog-conventionalcommits@9 \
      @semantic-release/release-notes-generator@14 \
      @semantic-release/gitlab@13 \
      @semantic-release/commit-analyzer@13

# Symlink OpenJDK binaries to systemic path and export environment variables
RUN ln -s /usr/lib/jvm/openjdk-17/bin/* /usr/local/bin/
ENV JAVA_HOME=/usr/lib/jvm/openjdk-17
ENV PATH="${JAVA_HOME}/bin:/usr/local/bin:${PATH}"

# Rootless Buildah-friendly setup
RUN useradd -m -u 10000 -s /bin/bash build && \
    touch /etc/subuid /etc/subgid && \
    echo build:10000:65536 > /etc/subuid && \
    echo build:10000:65536 > /etc/subgid && \
    chmod g=u /etc/subuid /etc/subgid /etc/passwd && \
    mkdir -p /home/build/.config/containers /workspace && \
    chown -R build:build /home/build /workspace

RUN printf '%s\n' 'export BUILDAH_ISOLATION=chroot' >> /home/build/.bashrc && \
    printf '%s\n' '[storage]' 'driver = "vfs"' > /home/build/.config/containers/storage.conf

RUN chmod +x /usr/local/bin/*

# Validation
RUN docker --version; \
    kubectl version --client; \
    kind version; \
    helm version; \
    kube-linter version; \
    argocd version --client || true; \
    kustomize version; \
    newman --version; \
    bru --version; \
    java -version; \
    mvn -version; \
    podman --version; \
    buildah --version; \
    oc version --client || true; \
    skopeo --version || true; \
    roxctl version || true; \
    blackduck --help || true

USER build
WORKDIR /home/build
CMD ["bash"]
