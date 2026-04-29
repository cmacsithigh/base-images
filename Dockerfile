# Stage 1: Build Node tools
FROM node:24 AS node-tools
# Pinned for Renovate tracking
ARG NEWMAN_VERSION=6.2.2
ARG BRUNO_VERSION=3.3.0

RUN npm install -g "newman@${NEWMAN_VERSION}"
RUN npm install -g "@usebruno/cli@${BRUNO_VERSION}"

# Stage 2: Fetch Binary Tools
FROM fedora:44 AS binfetch
# Kubernetes 1.32 compatible toolset
ARG ARGOCD_VERSION=v3.3.8
ARG KUSTOMIZE_VERSION=v5.8.1
ARG KIND_VERSION=v0.27.0

RUN dnf -y install ca-certificates curl gzip tar && dnf clean all

# Argo CD CLI
RUN curl -fsSL -o /usr/local/bin/argocd "https://github.com/argoproj/argo-cd/releases/download/${ARGOCD_VERSION}/argocd-linux-amd64" && \
    chmod +x /usr/local/bin/argocd

# Kind CLI (v0.27.0 supports K8s 1.32)
RUN curl -fsSL -o /usr/local/bin/kind "https://github.com/kubernetes-sigs/kind/releases/download/${KIND_VERSION}/kind-linux-amd64" && \
    chmod +x /usr/local/bin/kind

# Kustomize
RUN curl -fsSL "https://raw.githubusercontent.com/kubernetes-sigs/kustomize/master/hack/install_kustomize.sh" | bash -s -- "${KUSTOMIZE_VERSION#v}" && \
    mv kustomize /usr/local/bin/kustomize && \
    chmod +x /usr/local/bin/kustomize

# Stage 3: Final Image
FROM fedora:44
RUN dnf -y install \
    ca-certificates \
    bash \
    git \
    curl \
    shadow-utils \
    libstdc++ \
    && dnf clean all

# Copy tools from external images
COPY --from=docker.io/library/docker:26-cli /usr/local/bin/docker /usr/local/bin/docker
# Using the official K8s registry for v1.32.0
COPY --from=registry.k8s.io/kubectl:v1.32.0 /bin/kubectl /usr/local/bin/kubectl
COPY --from=docker.io/alpine/helm:4.1.1 /usr/bin/helm /usr/local/bin/helm

# Copy tools from previous stages
COPY --from=binfetch /usr/local/bin/argocd /usr/local/bin/argocd
COPY --from=binfetch /usr/local/bin/kustomize /usr/local/bin/kustomize
COPY --from=binfetch /usr/local/bin/kind /usr/local/bin/kind
COPY --from=node-tools /usr/local/bin/node /usr/local/bin/node
COPY --from=node-tools /usr/local/bin/newman /usr/local/bin/newman
COPY --from=node-tools /usr/local/bin/bru /usr/local/bin/bru
COPY --from=node-tools /usr/local/lib/node_modules /usr/local/lib/node_modules

ENV NODE_PATH=/usr/local/lib/node_modules
ENV PATH="/usr/local/bin:${PATH}"

# Validation check
RUN docker --version && \
    kubectl version --client=true && \
    kind version && \
    helm version && \
    argocd version --client || true && \
    kustomize version && \
    node --version && \
    newman --version && \
    bru --version

WORKDIR /workspace
CMD ["bash"]
