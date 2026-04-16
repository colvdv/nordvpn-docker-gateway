FROM ubuntu:24.04@sha256:3a4c9877b483ab46d7c3fbe165a0db275e1ae3cfe56a5657e5a47c2f99a99d1e

LABEL maintainer="COLVDV" \
      version="1.1.0" \
      description="NordVPN Docker Gateway with Meshnet"

# Install dependencies and NordVPN in a single clean layer
RUN apt-get update && apt-get install -y --no-install-recommends \
    wget \
    apt-transport-https \
    ca-certificates \
    iproute2 \
    iptables \
    && wget -qO /etc/apt/trusted.gpg.d/nordvpn_public.asc https://repo.nordvpn.com/gpg/nordvpn_public.asc \
    && echo "deb https://repo.nordvpn.com/deb/nordvpn/debian stable main" > /etc/apt/sources.list.d/nordvpn.list \
    && apt-get update \
    # Specify desired NordVPN version; 4.5.0 is the latest as of this writing and is stable.
    && apt-get install -y --no-install-recommends nordvpn=4.5.0 \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# The Anchor: Starts the service, waits for initialization, then stays alive
ENTRYPOINT ["/bin/bash", "-c", "\
    rm -rf /run/nordvpn && mkdir -p /run/nordvpn && \
    /etc/init.d/nordvpn start && \
    timeout 30 bash -c 'until nordvpn status &>/dev/null; do sleep 1; done' && \
    trap '/etc/init.d/nordvpn stop; exit 0' SIGTERM SIGINT; \
    while true; do sleep 10 & wait $!; done"]
