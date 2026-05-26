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

# Stage 2: Binary Fetcher (Static Go-based tools)
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

# Stage 3: Final Production Image
FROM fedora:44

# Essential runtime libs only (NO NODEJS NEEDED!)
RUN dnf -y install --setopt=install_weak_deps=False \
    ca-certificates bash git curl shadow-utils libstdc++ libatomic \
    && dnf clean all && rm -rf /var/cache/dnf

# 1. Copy Docker/K8s/Helm from official static images
COPY --from=docker.io/library/docker:26-cli /usr/local/bin/docker /usr/local/bin/docker
COPY --from=registry.k8s.io/kubectl:v1.32.0 /bin/kubectl /usr/local/bin/kubectl
COPY --from=docker.io/alpine/helm:4.1.1 /usr/bin/helm /usr/local/bin/helm

# 2. Copy tools from binfetch
COPY --from=binfetch /usr/local/bin/argocd /usr/local/bin/argocd
COPY --from=binfetch /usr/local/bin/kind /usr/local/bin/kind
COPY --from=binfetch /usr/local/bin/kustomize /usr/local/bin/kustomize

# 3. Copy our "Truly Single" Binaries
COPY --from=builder /build/newman_bin /usr/local/bin/newman

ARG BRUNO_VERSION=3.3.0

RUN dnf -y install --setopt=install_weak_deps=False \
    ca-certificates bash git curl shadow-utils libstdc++ libatomic \
    nodejs npm \
    && dnf clean all && rm -rf /var/cache/dnf

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
    argocd version --client || true; \
    kustomize version; \
    newman --version; \
    bru --version

WORKDIR /workspace
CMD ["bash"]
