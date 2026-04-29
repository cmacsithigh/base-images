# Stage 1: Node tools
FROM node:24 AS node-tools
# renovate: datasource=npm depName=newman
ARG NEWMAN_VERSION=6.2.2
# renovate: datasource=npm depName=@usebruno/cli
ARG BRUNO_VERSION=3.3.0

RUN npm install -g "newman@${NEWMAN_VERSION}" "@usebruno/cli@${BRUNO_VERSION}"

# Stage 2: Binary Tools
FROM fedora:44 AS binfetch
RUN dnf -y install ca-certificates curl gzip tar && dnf clean all

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
RUN dnf -y install \
    ca-certificates \
    bash \
    git \
    curl \
    shadow-utils \
    libstdc++ \
    libatomic \
    procps-ng \
    && dnf clean all

COPY --from=docker.io/library/docker:26-cli /usr/local/bin/docker /usr/local/bin/docker
COPY --from=registry.k8s.io/kubectl:v1.32.0 /bin/kubectl /usr/local/bin/kubectl
COPY --from=docker.io/alpine/helm:4.1.1 /usr/bin/helm /usr/local/bin/helm

COPY --from=binfetch /usr/local/bin/argocd /usr/local/bin/argocd
COPY --from=binfetch /usr/local/bin/kustomize /usr/local/bin/kustomize
COPY --from=binfetch /usr/local/bin/kind /usr/local/bin/kind

COPY --from=node-tools /usr/local/bin/node /usr/local/bin/node
COPY --from=node-tools /usr/local/lib/node_modules /usr/local/lib/node_modules

# Manually link Node binaries to ensure they point to the correct internal paths
RUN ln -sf /usr/local/lib/node_modules/newman/bin/newman.js /usr/local/bin/newman && \
    ln -sf /usr/local/lib/node_modules/@usebruno/cli/bin/cli.js /usr/local/bin/bru && \
    chmod +x /usr/local/bin/newman /usr/local/bin/bru

ENV NODE_PATH=/usr/local/lib/node_modules
ENV PATH="/usr/local/bin:${PATH}"

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
