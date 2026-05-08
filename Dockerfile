FROM ubuntu:24.04@sha256:c4a8d5503dfb2a3eb8ab5f807da5bc69a85730fb49b5cfca2330194ebcc41c7b

LABEL org.opencontainers.image.authors="COLVDV" \
      org.opencontainers.image.title="NordVPN Docker Gateway" \
      org.opencontainers.image.description="NordVPN Docker Gateway with Meshnet" \
      org.opencontainers.image.version="1.2.0" \
      org.opencontainers.image.url="https://github.com/colvdv/nordvpn-docker-gateway" \
      org.opencontainers.image.licenses="MIT" \
      capabilities.net_admin="required" \
      capabilities.net_raw="required"

# Optimized build layer
RUN apt-get update && apt-get install -y --no-install-recommends \
    wget \
    gnupg \
    ca-certificates \
    iproute2 \
    iptables \
    && mkdir -p -m 0700 /root/.gnupg \
    && wget -qO /tmp/nordvpn.asc https://repo.nordvpn.com/gpg/nordvpn_public.asc \
    # Verify fingerprint to prevent MITM attacks
    && gpg --dry-run --quiet --import --import-options show-only /tmp/nordvpn.asc | grep -q "BC5480EFEC5C081CE5BCFBE26B219E535C964CA1" \
    && cat /tmp/nordvpn.asc | gpg --dearmor > /usr/share/keyrings/nordvpn-keyring.gpg \
    && echo "deb [arch=amd64 signed-by=/usr/share/keyrings/nordvpn-keyring.gpg] https://repo.nordvpn.com/deb/nordvpn/debian stable main" > /etc/apt/sources.list.d/nordvpn.list \
    && apt-get update \
    # Pinned to specific NordVPN version (4.6.0, the latest as of this writing) for reproducibility. Check https://nordvpn.com/blog/nordvpn-linux-release-notes/ or remove the version tag to pull the latest Linux release version.
    && apt-get install -y --no-install-recommends nordvpn=4.6.0 \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/* /tmp/nordvpn.asc /root/.gnupg

# HEALTHCHECK: Ensures the daemon is responsive and NordVPN is in a valid state
HEALTHCHECK --interval=30s --timeout=10s --retries=3 \
    CMD nordvpn status | grep -qE "Status: Disconnected|Status: Connected" || exit 1

# Entrypoint Logic
# Clears stale PID/socket files to prevent startup failure after unclean shutdowns
# Polls for daemon readiness before proceeding
# Graceful shutdown handler
ENTRYPOINT ["/bin/bash", "-c", \
    "rm -rf /run/nordvpn && mkdir -p /run/nordvpn && \
    /etc/init.d/nordvpn start && \
    timeout 30 bash -c 'until nordvpn status &>/dev/null; do sleep 1; done' && \
    trap '/etc/init.d/nordvpn stop; exit 0' SIGTERM SIGINT; \
    while true; do sleep 10 & wait $!; done"]
