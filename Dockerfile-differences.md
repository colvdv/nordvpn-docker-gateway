## The OFFICIAL NordVPN Dockerfile vs. Our Custom Dockerfile (v1.2.5)
Here are the specific differences between the two `Dockerfile`s broken down by category:

### 1. Security & Image Integrity
[Our Custom Dockerfile](https://github.com/colvdv/nordvpn-docker-gateway/blob/main/Dockerfile) implements enterprise-grade security measures that [NordVPN's OFFICIAL Dockerfile](https://support.nordvpn.com/hc/en-us/articles/20465811527057-How-to-build-the-NordVPN-Docker-image) overlooks.
 - **Immutable Base Image:** We use a specific multi-arch digest (`ubuntu:24.04@sha256:c4a8d5503dfb2a3eb8ab5f807da5bc69a85730fb49b5cfca2330194ebcc41c7b`) rather than a generic tag. This ensures that every build is identical and protected against "poisoned" base image updates.
 - **GPG Fingerprint Verification:** Before installing the NordVPN package, our script performs a dry-run GPG import to verify the public key fingerprint. This prevents Man-in-the-Middle (MITM) attacks during the build process.
 - **Modern Keyring Management:** We follow the latest Debian/Ubuntu security standards by using `/usr/share/keyrings/` and the `signed-by` flag, rather than the deprecated `apt-key` or `trusted.gpg.d` methods used in the OFFICIAL script.
 - **Least Privilege Execution:** Unlike the official image which runs everything as `root`, our version creates a dedicated `norduser` and uses `gosu` to drop privileges, significantly reducing the attack surface.
 - **Self-Documenting Metadata:** We include standard OCI (Open Container Initiative) `LABEL` definitions to declare authorship, licensing, and explicitly document the required `NET_ADMIN` and `NET_RAW` Linux capabilities.
 
### 2. Package Management & Reproducibility
While the OFFICIAL Dockerfile contains redundancies, our Custom Dockerfile focuses on optimization and predictable deployments.
 - **Version Pinning:** Our script pins the client to a specific version (`nordvpn=4.6.0`). This prevents "broken builds" caused by unexpected upstream updates, ensuring consistent behavior across all deployments.
 - **Optimized Build Layer:** We consolidated dependencies into a single layer and removed the redundant `apt-get install` calls found in the OFFICIAL version (which literally runs the exact same string twice). We also systematically clean up build-only artifacts like the `.asc` file and `.gnupg` folder to keep image size minimal.
 - **Networking Toolset:** We explicitly include `iproute2` and `iptables`. These are essential for the VPN client to manipulate routing tables and firewall rules, which are necessary to establish a functional tunnel.

### 3. Service Reliability & Health Monitoring
A container that "starts" isn't always "working." Our Custom Dockerfile adds intelligence to the container lifecycle.
 - **Automated Healthcheck:** We include a `HEALTHCHECK` instruction that polls the NordVPN daemon status via `gosu` every 30 seconds. If the daemon crashes, Docker can automatically flag the container as unhealthy or trigger a restart.
 - **Daemon Readiness Polling:** The OFFICIAL script uses a blunt, arbitrary `sleep 5` to wait for the service. Our Custom script uses a smart `until` loop wrapped in a 30-second `timeout` window, proceeding exactly when the daemon is ready.
 - **Pre-Flight Validation:** Our entrypoint explicitly asserts environment readiness by verifying `iptables` capability and checking for the `/dev/net/tun` device immediately. Instead of failing cryptically down the line, it alerts the operator with precise error logs right away.

### 4. Signal Handling & Persistence
The method of execution determines how the container responds to the environment.
 - **Stale File Cleanup:** We explicitly run `rm -rf /run/nordvpn` at startup. This prevents the "stale socket" or lingering PID errors that cause the OFFICIAL container to fall into an unrecoverable boot loop if it wasn't shut down gracefully in a previous session.
 - **Graceful Shutdown & Signal Trapping:** Our Custom Dockerfile passes execution via an explicit `bash -c` shell running as PID 1 to trap `SIGTERM` and `SIGINT`. This allows the container to catch stop signals from Docker, cleanly stopping the daemon via `/etc/init.d/nordvpn stop` to prevent routing hang-ups or IP leaks on the host.
 - **Service-Oriented Loop:** Instead of dropping into a generic bash shell, our version uses a non-blocking `while loop` that monitors the daemon. This keeps the container alive permanently as a stable, hands-off network gateway.
