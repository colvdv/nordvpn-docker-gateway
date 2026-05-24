# REQUIRED RUNTIME ARGUMENTS:
# --cap-add=NET_ADMIN 
# --cap-add=NET_RAW
# --device /dev/net/tun
#
# JUSTIFICATION:
# NET_ADMIN: Required for NordVPN to modify routing tables and iptables.
# NET_RAW: Required for NordVPN to create and manage raw sockets.
# /dev/net/tun: Required for the creation of the VPN tunnel interface.

FROM ubuntu:24.04@sha256:c4a8d5503dfb2a3eb8ab5f807da5bc69a85730fb49b5cfca2330194ebcc41c7b

LABEL org.opencontainers.image.authors="COLVDV" \
      org.opencontainers.image.title="NordVPN Docker Gateway" \
      org.opencontainers.image.description="NordVPN Docker Gateway with Meshnet" \
      org.opencontainers.image.version="1.2.4" \
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
    gosu \
    && mkdir -p -m 0700 /root/.gnupg \
    && wget -qO /tmp/nordvpn.asc https://repo.nordvpn.com/gpg/nordvpn_public.asc \
    # Verify fingerprint to prevent MITM attacks
    && gpg --dry-run --quiet --import --import-options show-only /tmp/nordvpn.asc | grep -q "BC5480EFEC5C081CE5BCFBE26B219E535C964CA1" \
   && gpg --dearmor < /tmp/nordvpn.asc > /usr/share/keyrings/nordvpn-keyring.gpg \
    && echo "deb [arch=amd64 signed-by=/usr/share/keyrings/nordvpn-keyring.gpg] https://repo.nordvpn.com/deb/nordvpn/debian stable main" > /etc/apt/sources.list.d/nordvpn.list \
    && apt-get update \
    # Pinned to specific NordVPN version (4.6.0, the latest as of this writing) for reproducibility. Check https://nordvpn.com/blog/nordvpn-linux-release-notes/ or remove the version tag to pull the latest Linux release version.
    && apt-get install -y --no-install-recommends nordvpn=4.6.0 \
    # Create a non-privileged user and add them to the 'nordvpn' group
    && groupadd -r norduser && useradd -m -g norduser -G nordvpn norduser \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/* /tmp/nordvpn.asc /root/.gnupg

# HEALTHCHECK: Uses gosu to check status as the non-privileged user
HEALTHCHECK --interval=30s --timeout=10s --retries=3 \
    CMD gosu norduser nordvpn status | grep -qE "Status: Disconnected|Status: Connected" || exit 1

# ENTRYPOINT LOGIC
# 1. Environment & Capability Verification (NET_ADMIN, NET_RAW, and TUN device)
# 2. State Cleansing (Wipes stale PID/socket files to prevent boot loops after crashes)
# 3. Interruptible Signal Trap Management (Captures SIGTERM/SIGINT as PID 1 root shell)
# 4. Privileged Initialization (Spins up daemon and checks readiness as norduser via gosu)
# 5. Non-Privileged Persistent Monitoring (Spawns a background health loop as norduser)
# 6. Safe Shell Supervision (Root process blocks responsively via wait, ensuring clean teardown)
ENTRYPOINT ["/usr/bin/env", "bash", "-c", \
    "set -e; \
    if ! iptables -L -n > /dev/null 2>&1; then echo 'ERROR: Missing capabilities.'; exit 1; fi; \
    if [ ! -c /dev/net/tun ]; then echo 'ERROR: /dev/net/tun not found.'; exit 1; fi; \
    rm -rf /run/nordvpn && mkdir -p /run/nordvpn && \
    chown -R root:nordvpn /run/nordvpn /var/lib/nordvpn && \
    chmod 770 /run/nordvpn /var/lib/nordvpn; \
    \
    trap 'echo \"SIGTERM received. Stopping NordVPN daemon gracefully as root...\"; /etc/init.d/nordvpn stop; exit 0' SIGTERM SIGINT; \
    \
    /etc/init.d/nordvpn start; \
    \
    timeout 30 gosu norduser bash -c 'until nordvpn status &>/dev/null; do sleep 1; done'; \
    echo 'Initialization complete. Launching persistent monitor...'; \
    \
    gosu norduser bash -c 'while true; do if ! nordvpn status | grep -qE \"Status: Disconnected|Status: Connected\"; then exit 1; fi; sleep 5; done' & \
    MONITOR_PID=$!; \
    \
    while kill -0 $MONITOR_PID 2>/dev/null; do \
        sleep 2 & wait $!; \
    \
    done; \
    \
    trap - SIGTERM SIGINT; \
    echo 'NordVPN client reporting unhealthy status. Exiting.'; \
    /etc/init.d/nordvpn stop; \
    exit 1"]
