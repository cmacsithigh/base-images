# Stage 1: Fetch and Extract Binaries
FROM fedora:44 AS binfetch
# Added cpio to the install list
RUN dnf -y install ca-certificates curl gzip tar cpio && dnf clean all

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

# Bruno RPM Handling
# renovate: datasource=github-releases depName=usebruno/bruno
ARG BRUNO_VERSION=v3.3.0
RUN curl -fsSL -o /tmp/bruno.rpm "https://github.com/usebruno/bruno/releases/download/${BRUNO_VERSION}/bruno_${BRUNO_VERSION#v}_x86_64_linux.rpm"

# Extract only the JS application files from the RPM
RUN mkdir -p /tmp/extract && cd /tmp/extract && \
    rpm2cpio /tmp/bruno.rpm | cpio -idmv && \
    mkdir -p /usr/local/lib/bruno-cli && \
    cp -r usr/lib/bruno/resources/app/* /usr/local/lib/bruno-cli/

# Stage 2: Final Image
FROM fedora:44

# Minimal runtime dependencies
RUN dnf -y install --setopt=install_weak_deps=False \
    ca-certificates \
    bash \
    git \
    curl \
    shadow-utils \
    libstdc++ \
    libatomic \
    nodejs \
    && dnf clean all && rm -rf /var/cache/dnf

# 1. Copy CLI tools from external images
COPY --from=docker.io/library/docker:26-cli /usr/local/bin/docker /usr/local/bin/docker
COPY --from=registry.k8s.io/kubectl:v1.32.0 /bin/kubectl /usr/local/bin/kubectl
COPY --from=docker.io/alpine/helm:4.1.1 /usr/bin/helm /usr/local/bin/helm

# 2. Copy tools from binfetch stage
COPY --from=binfetch /usr/local/bin/argocd /usr/local/bin/argocd
COPY --from=binfetch /usr/local/bin/kustomize /usr/local/bin/kustomize
COPY --from=binfetch /usr/local/bin/kind /usr/local/bin/kind

# 3. Copy Newman (Alpine-sourced JS files)
COPY --from=postman/newman:latest /usr/local/lib/node_modules /usr/local/lib/node_modules
RUN ln -sf /usr/local/lib/node_modules/newman/bin/newman.js /usr/local/bin/newman && \
    chmod +x /usr/local/bin/newman

# 4. Copy Bruno (Extracted JS files)
COPY --from=binfetch /usr/local/lib/bruno-cli /usr/local/lib/bruno-cli
RUN ln -sf /usr/local/lib/bruno-cli/bin/cli.js /usr/local/bin/bru && \
    chmod +x /usr/local/bin/bru

# Final Environment Setup
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
