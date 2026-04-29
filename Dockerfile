# Stage 1: Bun Builder - Compiles JS into standalone binaries
FROM oven/bun:1.2 AS builder

ARG BRUNO_VERSION=3.3.0
ARG NEWMAN_VERSION=6.2.2

WORKDIR /build

# 1. Create package.json to ensure predictable module structure
RUN echo "{\"dependencies\": {\"@usebruno/cli\": \"${BRUNO_VERSION}\", \"newman\": \"${NEWMAN_VERSION}\"}}" > package.json

# 2. Install dependencies and trust post-install scripts
RUN bun install && bun pm trust --all

# 3. Compile Bruno CLI into a single-file binary
# target bun-linux-x64 creates a standalone executable including the runtime
RUN bun build ./node_modules/@usebruno/cli/bin/cli.js \
    --compile --target=bun-linux-x64 --outfile bru

# 4. Compile Newman into a single-file binary
RUN bun build ./node_modules/newman/bin/newman.js \
    --compile --target=bun-linux-x64 --outfile newman

# Stage 2: Binary Fetcher - Collects Go/C++ based static tools
FROM fedora:44 AS binfetch
RUN dnf -y install ca-certificates curl && dnf clean all

# ArgoCD
ARG ARGOCD_VERSION=v3.3.8
RUN curl -fsSL -o /usr/local/bin/argocd "https://github.com/argoproj/argo-cd/releases/download/${ARGOCD_VERSION}/argocd-linux-amd64" && \
    chmod +x /usr/local/bin/argocd

# Kind
ARG KIND_VERSION=v0.27.0
RUN curl -fsSL -o /usr/local/bin/kind "https://github.com/kubernetes-sigs/kind/releases/download/${KIND_VERSION}/kind-linux-amd64" && \
    chmod +x /usr/local/bin/kind

# Kustomize
ARG KUSTOMIZE_VERSION=v5.8.1
RUN curl -fsSL "https://raw.githubusercontent.com/kubernetes-sigs/kustomize/master/hack/install_kustomize.sh" | bash -s -- "${KUSTOMIZE_VERSION#v}" && \
    mv kustomize /usr/local/bin/kustomize && \
    chmod +x /usr/local/bin/kustomize

# Stage 3: Final Production Image
FROM fedora:44

# Essential runtime libraries only (No nodejs required anymore!)
RUN dnf -y install --setopt=install_weak_deps=False \
    ca-certificates \
    bash \
    git \
    curl \
    shadow-utils \
    libstdc++ \
    libatomic \
    && dnf clean all && rm -rf /var/cache/dnf

# 1. Copy Docker/K8s/Helm from official images
COPY --from=docker.io/library/docker:26-cli /usr/local/bin/docker /usr/local/bin/docker
COPY --from=registry.k8s.io/kubectl:v1.32.0 /bin/kubectl /usr/local/bin/kubectl
COPY --from=docker.io/alpine/helm:4.1.1 /usr/bin/helm /usr/local/bin/helm

# 2. Copy ArgoCD, Kind, and Kustomize from binfetch
COPY --from=binfetch /usr/local/bin/argocd /usr/local/bin/argocd
COPY --from=binfetch /usr/local/bin/kind /usr/local/bin/kind
COPY --from=binfetch /usr/local/bin/kustomize /usr/local/bin/kustomize

# 3. Copy the Single-File Binaries created by Bun
# These are real files, not symlinks. Perfect for 'docker cp'.
COPY --from=builder /build/bru /usr/local/bin/bru
COPY --from=builder /build/newman /usr/local/bin/newman

# Final permissions and path setup
RUN chmod +x /usr/local/bin/*
ENV PATH="/usr/local/bin:${PATH}"

# Validation Check
# Using '|| true' on ArgoCD as it often tries to connect to a server for version info
RUN docker --version && \
    kubectl version --client && \
    kind version && \
    helm version && \
    argocd version --client || true && \
    kustomize version && \
    newman --version && \
    bru --version

WORKDIR /workspace
CMD ["bash"]
