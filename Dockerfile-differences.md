## The OFFICIAL NordVPN Dockerfile vs. Our Custom Dockerfile
Here are the specific differences between the two `Dockerfile`s broken down by category:

### 1. Security & Image Integrity
[Our Custom Dockerfile](https://github.com/colvdv/nordvpn-docker-gateway/blob/main/Dockerfile) implements enterprise-grade security measures that [NordVPN's OFFICIAL Dockerfile](https://support.nordvpn.com/hc/en-us/articles/20465811527057-How-to-build-the-NordVPN-Docker-image) overlooks.
 - **Immutable Base Image:** We use a specific digest (`ubuntu:24.04@sha256:...`) rather than a generic tag. This ensures that every build is identical and protected against "poisoned" base image updates.
 - **GPG Fingerprint Verification:** Before installing the NordVPN package, our script performs a dry-run GPG import to verify the public key fingerprint. This prevents Man-in-the-Middle (MITM) attacks during the build process.
 - **Modern Keyring Management:** We follow the latest Debian/Ubuntu security standards by using `/usr/share/keyrings/` and the `signed-by` flag, rather than the deprecated `apt-key` or `trusted.gpg.d` methods used in the OFFICIAL script.
 - **Least Privilege Execution:** Unlike the official image which runs everything as `root`, our version creates a dedicated `norduser` and uses `gosu` to drop privileges, significantly reducing the attack surface.
 
### 2. Package Management & Reproducibility
While the OFFICIAL Dockerfile contains redundancies, our Custom Dockerfile focuses on optimization and predictable deployments.
 - **Version Pinning:** Our script pins the client to a specific version (`nordvpn=4.6.0`). This prevents "broken builds" caused by unexpected upstream updates, ensuring consistent behavior across all deployments.
 - **Optimized Build Layer:** We consolidated dependencies into a single layer and removed the redundant `apt-get install` calls found in the OFFICIAL version.
 - **Networking Toolset:** We include `iproute2` and `iptables`. These are essential for the VPN client to manipulate routing tables and firewall rules, which are necessary to establish a functional tunnel.

### 3. Service Reliability & Health Monitoring
A container that "starts" isn't always "working." Our Custom Dockerfile adds intelligence to the container lifecycle.
 - **Automated Healthcheck:** We include a `HEALTHCHECK` instruction that polls the NordVPN daemon every 30 seconds. If the daemon crashes or loses its connection state, Docker can automatically flag the container as unhealthy or trigger a restart.
 - **Daemon Readiness Polling:** The OFFICIAL script uses a blunt `sleep 5` to wait for the service. Our Custom script uses a smart `until` loop that polls the daemon’s status, proceeding only when the service is actually ready.
 - **Pre-Flight Validation:** Our entrypoint checks for required `NET_ADMIN` capabilities and the `/dev/net/tun` device immediately. Instead of failing silently or cryptically, it provides clear error messages if the environment is not configured correctly.

### 4. Signal Handling & Persistence
The method of execution determines how the container responds to the environment.
 - **Stale File Cleanup:** We explicitly run `rm -rf /run/nordvpn` at startup. This prevents the "stale socket" error that often causes the OFFICIAL container to fail if it wasn't shut down gracefully in a previous session.
 - **Graceful Shutdown:** Our Custom Dockerfile uses a `trap` for `SIGTERM` and `SIGINT`. This allows the NordVPN service to trigger its official stop script and disconnect cleanly when the container is stopped, preventing IP leaks or routing hang-ups.
 - **Service-Oriented Loop:** Instead of dropping into a generic bash shell, our version uses a non-blocking `while loop` that monitors the `nordvpnd` process. This keeps the container alive as a stable network gateway, ensuring an "always-on" architecture for your services.
