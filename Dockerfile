FROM fedora:44 as binfetch

RUN dnf -y install ca-certificates curl tar gzip && dnf clean all

ARG KIND_VERSION=v0.33.0
RUN curl -fsSL -o /usr/local/bin/kind "https://github.com/kubernetes-sigs/kind/releases/download/${KIND_VERSION}/kind-linux-amd64" && \
    chmod +x /usr/local/bin/kind

ARG KUSTOMIZE_VERSION=v5.8.1
RUN curl -fsSL "https://raw.githubusercontent.com/kubernetes-sigs/kustomize/master/hack/install_kustomize.sh" | bash -s -- "${KUSTOMIZE_VERSION#v}" && \
    mv kustomize /usr/local/bin/kustomize && \
    chmod +x /usr/local/bin/kustomize

# Stage 3: Final Production Image
FROM fedora:44

# Essential runtime libs only
RUN dnf -y install --setopt=install_weak_deps=False \
    ca-certificates bash git curl shadow-utils shadow-utils-subid libstdc++ libatomic \
    && dnf clean all && rm -rf /var/cache/dnf

COPY --from=binfetch /usr/local/bin/kind /usr/local/bin/kind
COPY --from=binfetch /usr/local/bin/kustomize /usr/local/bin/kustomize

RUN chmod +x /usr/local/bin/*

# Validation
RUN kind version; \
    kustomize version

USER build
WORKDIR /home/build
CMD ["bash"]
