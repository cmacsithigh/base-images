# Stage 1: Build Node tools
FROM node:24 AS node-tools
ARG NEWMAN_VERSION=latest
ARG BRUNO_VERSION=latest

# Newman (Postman CLI)
RUN if [ "$NEWMAN_VERSION" = "latest" ]; then \
    npm install -g newman; \
    else \
    npm install -g "newman@${NEWMAN_VERSION}"; \
    fi

# Bruno CLI (provides `bru`)
RUN if [ "$BRUNO_VERSION" = "latest" ]; then \
    npm install -g @usebruno/cli; \
    else \
    npm install -g "@usebruno/cli@${BRUNO_VERSION}"; \
    fi

# Stage 2: Fetch Binary Tools
FROM fedora:44 AS binfetch
ARG ARGOCD_VERSION=latest
ARG KUSTOMIZE_VERSION=latest

RUN dnf -y install ca-certificates curl gzip tar && dnf clean all

# Argo CD CLI
RUN set -eux; \
    if [ "$ARGOCD_VERSION" = "latest" ]; then \
    ARGOCD_VERSION="v$(curl -fsSL https://raw.githubusercontent.com/argoproj/argo-cd/stable/VERSION)"; \
    fi; \
    curl -fsSL -o /usr/local/bin/argocd "https://github.com/argoproj/argo-cd/releases/download/${ARGOCD_VERSION}/argocd-linux-amd64"; \
    chmod +x /usr/local/bin/argocd

# Kustomize
RUN set -eux; \
    if [ "$KUSTOMIZE_VERSION" = "latest" ]; then \
    curl -fsSL "https://raw.githubusercontent.com/kubernetes-sigs/kustomize/master/hack/install_kustomize.sh" | bash; \
    mv kustomize /usr/local/bin/kustomize; \
    else \
    curl -fsSL "https://raw.githubusercontent.com/kubernetes-sigs/kustomize/master/hack/install_kustomize.sh" | bash -s -- "$KUSTOMIZE_VERSION"; \
    mv kustomize /usr/local/bin/kustomize; \
    fi; \
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
COPY --from=docker.io/bitnami/kubectl:1.30 /opt/bitnami/kubectl/bin/kubectl /usr/local/bin/kubectl
COPY --from=docker.io/kindest/node:v1.30.0 /usr/local/bin/kind /usr/local/bin/kind
COPY --from=docker.io/alpine/helm:3.15.3 /usr/bin/helm /usr/local/bin/helm

# Copy tools from previous stages
COPY --from=binfetch /usr/local/bin/argocd /usr/local/bin/argocd
COPY --from=binfetch /usr/local/bin/kustomize /usr/local/bin/kustomize
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
