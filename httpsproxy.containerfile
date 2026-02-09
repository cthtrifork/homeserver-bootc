FROM scratch AS ctx
COPY / /

FROM quay.io/fedora/fedora-bootc:45@sha256:357d075456d2a10a98f9bf01f79c0f08cbfab8251d6835141a6b26cb2307fc4f

#setup sudo to not require password
RUN echo "%wheel        ALL=(ALL)       NOPASSWD: ALL" > /etc/sudoers.d/wheel-sudo

# Write some metadata
RUN echo VARIANT="HTTPS Proxy (Squid) bootc OS" && echo VARIANT_ID=com.github.cthtrifork.httpsproxy >> /usr/lib/os-release

# Install squid and utilities
# https://docs.redhat.com/en/documentation/red_hat_enterprise_linux/9/html/deploying_web_servers_and_reverse_proxies/configuring-the-squid-caching-proxy-server_deploying-web-servers-and-reverse-proxies
RUN dnf -y install qemu-guest-agent firewalld squid policycoreutils-python-utils \
    tree rsync dnf-plugins-core procps-ng file && \
    dnf clean all

# Set timezone
RUN ln -sf /usr/share/zoneinfo/Europe/Copenhagen /etc/localtime

# Registry auth
ARG REGISTRY_URL
ARG REGISTRY_USERNAME

RUN --mount=type=secret,id=creds,required=true cp /run/secrets/creds /usr/lib/container-auth.json && \
    chmod 0600 /usr/lib/container-auth.json && \
    ln -sr /usr/lib/container-auth.json /etc/ostree/auth.json

# Install service
RUN --mount=type=bind,from=ctx,src=/,dst=/ctx \
    rsync -rvpK /ctx/system_files/httpsproxy/ /

# Cleanup
RUN --mount=type=bind,from=ctx,src=/,dst=/ctx \
    --mount=type=tmpfs,dst=/tmp \
    /ctx/build_files/cleanup.sh

RUN squid -k parse -f /etc/squid/squid.conf && \
	systemctl enable squid.service

# NetworkManager-wait-online is buggy so we disable it
RUN systemctl disable NetworkManager-wait-online.service \
  && systemctl mask NetworkManager-wait-online.service

# Networking
EXPOSE 3128
RUN firewall-offline-cmd --add-port 3128/tcp && \
    firewall-offline-cmd --add-service squid

# Clean up caches in the image and lint the container
RUN bootc container lint || true
