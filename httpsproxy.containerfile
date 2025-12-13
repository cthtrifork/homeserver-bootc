FROM scratch AS ctx
COPY / /

FROM quay.io/fedora/fedora-bootc:43

#setup sudo to not require password
RUN echo "%wheel        ALL=(ALL)       NOPASSWD: ALL" > /etc/sudoers.d/wheel-sudo

# Write some metadata
RUN echo VARIANT="HTTPS Proxy (Squid) bootc OS" && echo VARIANT_ID=com.github.cthtrifork.httpsproxy >> /usr/lib/os-release

# Install vmtoolsd and utilities
RUN dnf -y install qemu-guest-agent firewalld squid \
    tree rsync dnf-plugins-core procps-ng file && \
    systemctl enable squid.service && \
    dnf clean all

# Set timezone
RUN ln -sf /usr/share/zoneinfo/Europe/Copenhagen /etc/localtime

# Registry auth
ARG REGISTRY_URL
ARG REGISTRY_USERNAME

RUN --mount=type=secret,id=creds,required=true cp /run/secrets/creds /usr/lib/container-auth.json && \
    chmod 0600 /usr/lib/container-auth.json && \
    ln -sr /usr/lib/container-auth.json /etc/ostree/auth.json

# Squid dirs setup
RUN mkdir -p /var/log/squid/ /var/spool/squid && \
    chown -R squid:squid /var/spool/squid && \
    chmod -R 775 /var/spool/squid && \
    chown -R squid:squid /var/log/squid && \
    chmod -R 775 /var/log/squid

# Install service
RUN --mount=type=bind,from=ctx,src=/,dst=/ctx \
    rsync -rvpK /ctx/system_files/jumphost/ /

# Cleanup
RUN --mount=type=bind,from=ctx,src=/,dst=/ctx \
    --mount=type=tmpfs,dst=/tmp \
    /ctx/build_files/cleanup.sh 

# Networking
EXPOSE 3128
RUN firewall-offline-cmd --add-port 3128/tcp && \
    firewall-offline-cmd --add-service squid

# Clean up caches in the image and lint the container
RUN rm /var/{cache,lib}/dnf /var/lib/rhsm /var/cache/ldconfig -rf
RUN bootc container lint