# Stage 1: Tool Builder (NPM only lives here)
FROM node:24-slim AS builder
# renovate: datasource=npm depName=@usebruno/cli
ARG BRUNO_VERSION=3.3.0
# renovate: datasource=npm depName=newman
ARG NEWMAN_VERSION=6.2.2

# Install tools into a clean prefix
RUN npm install -g --prefix /node_tools \
    "@usebruno/cli@${BRUNO_VERSION}" \
    "newman@${NEWMAN_VERSION}"

# Stage 2: Binary Fetcher
FROM fedora:44 AS binfetch
RUN dnf -y install ca-certificates curl && dnf clean all

# renovate: datasource=github-releases depName=argoproj/argo-cd
ARG ARGOCD_VERSION=v3.3.8
RUN curl -fsSL -o /usr/local/bin/argocd "https://github.com/argoproj/argo-cd/releases/download/${ARGOCD_VERSION}/argocd-linux-amd64" && \
    chmod +x /usr/local/bin/argocd

# renovate: datasource=github-releases depName=kubernetes-sigs/kind
ARG KIND_VERSION=v0.27.0
RUN curl -fsSL -o /usr/local/bin/kind "https://github.com/kubernetes-sigs/kind/releases/download/${KIND_VERSION}/kind-linux-amd64" && \
    chmod +x /usr/local/bin/kind

# renovate: datasource=github-releases depName=kubernetes-sigs/kustomize
ARG KUSTOMIZE_VERSION=v5.8.1
RUN curl -fsSL "https://raw.githubusercontent.com/kubernetes-sigs/kustomize/master/hack/install_kustomize.sh" | bash -s -- "${KUSTOMIZE_VERSION#v}" && \
    mv kustomize /usr/local/bin/kustomize && \
    chmod +x /usr/local/bin/kustomize

# Stage 3: Final Image
FROM fedora:44

# Minimal runtime: nodejs is the only "heavy" requirement
RUN dnf -y install --setopt=install_weak_deps=False \
    ca-certificates bash git curl shadow-utils libstdc++ libatomic nodejs \
    && dnf clean all

# 1. Copy K8s/Docker/Helm binaries
COPY --from=docker.io/library/docker:26-cli /usr/local/bin/docker /usr/local/bin/docker
COPY --from=registry.k8s.io/kubectl:v1.32.0 /bin/kubectl /usr/local/bin/kubectl
COPY --from=docker.io/alpine/helm:4.1.1 /usr/bin/helm /usr/local/bin/helm

# 2. Copy tools from binfetch
COPY --from=binfetch /usr/local/bin/ /usr/local/bin/

# 3. Copy Node tools from builder
# This brings the JS code and the bin symlinks (bru, newman)
COPY --from=builder /node_tools/lib/node_modules /usr/local/lib/node_modules
COPY --from=builder /node_tools/bin/ /usr/local/bin/

# Environment Configuration
ENV NODE_PATH=/usr/local/lib/node_modules
ENV PATH="/usr/local/bin:${PATH}"

# Validation
RUN docker --version && \
    kubectl version --client && \
    kind version && \
    helm version && \
    argocd version --client || true && \
    kustomize version && \
    node --version && \
    newman --version && \
    bru --version

WORKDIR /workspace
CMD ["bash"]
