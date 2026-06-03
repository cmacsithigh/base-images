# Stage 1: Build the Single-File Binaries
FROM oven/bun:1.2 AS builder
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
RUN dnf -y install ca-certificates curl && dnf clean all

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

# Stage 3: Final Production Image
FROM fedora:44

# Essential runtime libs only
RUN dnf -y install --setopt=install_weak_deps=False \
    ca-certificates bash git curl shadow-utils libstdc++ libatomic \
    && dnf clean all && rm -rf /var/cache/dnf

# 1. Copy Docker/K8s/Helm from official static images
COPY --from=docker.io/library/docker:26-cli /usr/local/bin/docker /usr/local/bin/docker
COPY --from=registry.k8s.io/kubectl:v1.32.0 /bin/kubectl /usr/local/bin/kubectl
COPY --from=docker.io/alpine/helm:4.1.1 /usr/bin/helm /usr/bin/helm
COPY --from=docker.io/stackrox/kube-linter:v0.8.3 /kube-linter /usr/local/bin/kube-linter

# 2. Copy tools from binfetch (Includes Black Duck and Roxctl)
COPY --from=binfetch /usr/local/bin/argocd /usr/local/bin/argocd
COPY --from=binfetch /usr/local/bin/kind /usr/local/bin/kind
COPY --from=binfetch /usr/local/bin/kustomize /usr/local/bin/kustomize
COPY --from=binfetch /usr/local/bin/blackduck /usr/local/bin/blackduck
COPY --from=binfetch /usr/local/bin/roxctl /usr/local/bin/roxctl

# 3. Copy our "Truly Single" Binaries
COPY --from=builder /build/newman_bin /usr/local/bin/newman

ARG BRUNO_VERSION=3.3.0
ARG MAVEN_VERSION=3.9.9

# FIXED: Passing 'java-17' forces DNF's virtual provider mapping system to lock down OpenJDK 17 
RUN dnf -y install --setopt=install_weak_deps=False \
    nodejs npm \
    java-17 \
    maven \
    && dnf clean all && rm -rf /var/cache/dnf

# Install Bruno CLI
RUN npm config set update-notifier false && \
    npm config set fund false && \
    npm config set audit false && \
    npm install -g --prefix /usr/local @usebruno/cli@${BRUNO_VERSION} && \
    npm cache clean --force

RUN chmod +x /usr/local/bin/*
ENV PATH="/usr/local/bin:${PATH}"

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
    mvn -version; \
    roxctl version || true; \
    blackduck --help || true

WORKDIR /workspace
CMD ["bash"]
