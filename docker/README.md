# Running Pi Pocket with Docker Compose

`docker-compose.yml` at the repository root runs Pi Pocket with a browser of its own and gates every outbound
request through an allowlist. The app runs unprivileged on a read-only root filesystem, with a separate browser.
The MITM egress proxy also handles DNS interception. Only the reverse proxy is reachable from outside. A one-shot initializer
generates the egress CA on first startup and shares its public trust store through a named volume.

This page describes the stack. The short version is in the repository's README:

```bash
docker compose up --build
```

Then open the published address on the Docker host: <http://localhost:8787>.

## Requirements

- **Docker Engine 29 or newer.** The app image uses `COPY --parents`, which older engines do not understand.
- **Docker Compose v5** (`docker compose`).
- About 3 GB of memory for the default stack, most of it for the browser. The optional `agent` service has a 512 MB
  memory limit; allow for that separately when running it alongside the stack.
- A Compose provider that supports `depends_on: condition: service_completed_successfully`. Test this when using
  Podman Compose; provider implementations may differ.

## Services

| Service         | Built from / image                   | Networks           | Purpose                                                      |
| --------------- | ------------------------------------ | ------------------ | ------------------------------------------------------------ |
| `ca-init`       | `docker/ca-init.Dockerfile`          | none               | one-shot CA and system trust-store initialization            |
| `gateway`       | `ironsh/iron-proxy:0.56.0`           | internal, edge     | DNS interception and allowlisted HTTP/HTTPS MITM proxy        |
| `chrome`        | `docker/chrome.Dockerfile`           | internal           | browser with the proxy CA imported into its NSS database     |
| `app`           | `docker/Dockerfile`                  | internal           | Pi Pocket, running as `nonroot` (uid 65532)                 |
| `agent`         | `docker/pi-agent.Dockerfile`         | internal           | optional interactive Pi CLI, sharing sign-ins and workspace |
| `ingress`       | `nginxinc/nginx-unprivileged:alpine` | frontend, internal | reverse proxy; the only published port                      |

## Network isolation

Three networks separate ingress, the app, and egress. Only `edge` has a route to the internet, and only `ingress` is
reachable from the host.

```
                              host / LAN
                                  │
                          published :8787
                                  │
                                  ▼
                    ┌───────────────────────────┐
                    │ ingress                   │
                    │ nginx-unprivileged        │
                    │ frontend + internal       │
                    └─────────────┬─────────────┘
                                  │ http://app:8787
  ────────────────────────────────┼─────────────────────────────────────
  internal · 172.28.0.0/24 · internal: true — no route out
  ────────────────────────────────┼─────────────────────────────────────
                                  ▼
     ┌───────────────────────┐           ┌───────────────────────┐
     │ app                   │  CDP:9222 │ chrome                │
     │ Pi Pocket (nonroot)   ├──────────▶│ headless-shell        │
     │ /workspace (rw)       │           │ 172.28.0.10 (ro)      │
     │                       │           │ /workspace (ro)       │
     └───────────┬───────────┘           └───────────┬───────────┘
                 │                                   │
                 │                                   │
                 └───────────────┬───────────────────┘
                                 ▼
                      ┌───────────────────────┐
                      │ gateway               │
                      │ iron-proxy .11        │
                      │ DNS :53 / proxy :8888 │
                      │ direct HTTP(S) :80/443│
                      └───────────┬───────────┘
  ────────────────────────────────┼──────────────────────────────────
  edge · the only network with a route to the internet
  ────────────────────────────────┼──────────────────────────────────
                                  ▼
                              the internet
```

The optional `agent` service joins `internal` only. Like the app, it reaches the internet through the allowlisted
gateway; it is not started by the default `docker compose up`.

What can talk to what:

| From            | To              | Port | What                               |
| --------------- | --------------- | ---- | ---------------------------------- |
| host            | `ingress`       | 8787 | the published app                  |
| `ingress`       | `app`           | 8787 | reverse proxy                      |
| `app`           | `chrome`        | 9222 | the DevTools protocol              |
| `app`, `agent`, `chrome` | `gateway` | 53/UDP | DNS interception                   |
| `app`, `agent`, `chrome` | `gateway` | 8888   | explicit HTTP/HTTPS proxy          |
| `app`, `agent`, `chrome` | `gateway` | 80/443 | DNS-intercepted direct HTTP/HTTPS  |
| `gateway`       | internet        | 80/443 | allowed HTTP and HTTPS upstream requests |
| `gateway`       | runtime DNS     | 53   | upstream lookups for proxy requests |

What cannot happen:

- `app`, `chrome`, and `agent` cannot reach the internet directly. They are on `internal`, which has no route out;
  their only way out is `gateway`.
- `chrome`'s DevTools port 9222 is never published, and the endpoint has no authentication.
- 8787 is the only published port, and only `ingress` is on `frontend`.

## DNS and the egress allowlist

The runtime's embedded DNS resolves Compose service names. External A queries from the internal services go to
Iron-proxy at `172.28.0.11` and receive that same address, **including names not on the allowlist**. If changing
this address, update the gateway's Compose IP, client DNS setting, healthcheck and `docker/iron-proxy.yaml` together. The listener is
UDP-only and returns no AAAA address for intercepted names. This differs from dnsmasq: DNS no longer returns
NXDOMAIN for unlisted domains or the real address for listed ones. The gateway itself uses the runtime's upstream
resolver, not its own listener, so it can resolve real upstream addresses, including local names supplied by your
host's DNS.

Clients can use the explicit proxy on port 8888 or connect to an intercepted address on ports 80/443. In both cases,
`docker/iron-proxy.yaml` enforces the HTTP/HTTPS allowlist; an unlisted request is rejected by the proxy, not DNS.
Other direct internet traffic remains blocked by the internal network. Tools that need real DNS answers, DNS over
TCP, or non-HTTP protocols need a different arrangement. The proxy's DNS interception is not a DNS allowlist.

The defaults allow `radius.earendil.com`, `radius.pi.dev`, `pi.dev`, the listed GitHub hosts, the local Git host and
`api.typesafe.ai`. Edit the transform's `domains` or rules for your providers; the same file also configures secret
replacement. After editing it, recreate the gateway:

```bash
docker compose up -d --force-recreate gateway
```

When upgrading from the dnsmasq stack, remove the old container before starting the gateway, which takes over its
internal IP (the named volumes are preserved):

```bash
docker compose down --remove-orphans
docker compose up -d --build --remove-orphans
```

## Egress-proxy CA and trust

On startup, `ca-init` creates a P-256 CA if the private volume is empty and reuses it on subsequent starts. It fails
on an incomplete, expired, or mismatched pair. The initializer publishes the certificate alongside the Debian
system roots as both a combined PEM bundle and an OpenSSL hashed certificate directory. All long-running services
mount that public store read-only at `/etc/ssl/certs`; common OpenSSL, curl, Git and Python CA environment variables
point to it. The app and agent also receive `NODE_EXTRA_CA_CERTS`, and Chrome imports the CA into its NSS database
at each startup. Tools with their own independent trust stores may require additional configuration.

The key and certificate are persisted in `ca-private`, mounted only by `ca-init` and `gateway`. The key is readable
by the gateway's group (65534); the volume is not a substitute for protecting the container host or engine. Back up
the private volume securely. The public store in `ca-public` is rebuilt on initialization from the CA and the
initializer image's Debian CA package; it does not include custom roots added separately to other images. Rebuild the
initializer image to pick up updated system roots; stop the stack before updating them. Unchanged stores are left
in place when another Compose invocation starts. `IRON_PROXY_CA_DAYS` and `IRON_PROXY_CA_SUBJECT` affect newly
generated CAs only.

To rotate the CA, stop all services, securely back up the old private volume if needed, remove **only** the two CA
volumes, then start again (this creates a new CA without rebuilding client images):

```bash
docker compose down
docker volume rm pi-pocket_ca-private pi-pocket_ca-public
docker compose up -d --build
```

Chrome replaces its `iron-proxy` NSS entry on startup; the `chrome-nssdb` volume need not be deleted. Test browser
and shell-tool HTTPS after rotation. `docker compose down -v` also deletes the CA and all application data volumes.

If upgrading from the old file-based setup, the files `secrets/iron-proxy/ca.key` and
`docker/iron-proxy-ca.crt` are not imported or deleted: a new CA is generated. Securely archive or delete the old
key after the transition. The MITM proxy can see decrypted traffic; do not log credential headers or request bodies.

## Configuration files

The app and optional Pi CLI images bundle their defaults, while Compose mounts the deployment-specific proxy
configuration and CA:

- `docker/pi-pocket/config.json` — Pi Pocket's initial `config.json` with an owner user and the MCP extension
  enabled. Contains a default `ownerToken` ("letmein") for development; rotate it on first login.
- `docker/pi/agent/settings.json` — Pi agent settings, including `collapseChangelog: true` and `codemode`
  enabled by default via `defaultTools`; used by both the app and Pi CLI images.
- `docker/pi/agent/mcp.json` — MCP server configuration, pointing to the Radius MCP endpoint; used by both images.
- `src/pocket-mcp/` — the pinned pocket-mcp submodule. The image copies `mcp.ts` and `mcp/` into Pi Pocket's
  extensions directory.
- `docker/iron-proxy.yaml` — Iron-proxy listeners, CA paths, and initial host allowlist.
- `docker/ca-init.sh` and `docker/ca-init.Dockerfile` — initialize the CA and public trust store at startup.
- `docker/chrome-entrypoint.sh` — imports the current CA into Chrome's NSS database before launching.
- A remote extension (`whimsical.ts`) is fetched from GitHub at build time.

## Run the Pi CLI

The optional Pi CLI container uses the same `pi-data`, `pi-home`, and `pi-workspace` volumes as the app, so it shares
Pi's sign-ins and the working files. Start it interactively with:

```bash
docker compose --profile agent run --build --rm agent
```

The container targets `linux/amd64`, is available only on the internal network, and uses the same allowlisted
gateway for egress. On other host architectures it needs container-runtime emulation. `docker compose up` without the
`agent` profile does not start it.

## Data and the workspace

Named volumes hold state that must survive container recreation:

| Volume           | Mounted at                                    | Holds                                                                    |
| ---------------- | --------------------------------------------- | ------------------------------------------------------------------------ |
| `pi-home`        | `/home/nonroot`                               | `$HOME`: git config, SSH keys, package caches, and other per-user state  |
| `pi-data`        | `/home/nonroot/.pi`                           | Pi's sign-ins, models, skills, sessions, and MCP config                  |
| `pi-pocket-data` | `/home/nonroot/.pi-pocket`                    | Pi Pocket's `config.json`, `pocket.sqlite`, drop-ins, and themes         |
| `pi-workspace`   | `/workspace`                                  | the folder new sessions start in                                         |
| `chrome-nssdb`   | `/home/user/.local/share/pki/nssdb`           | Chrome's writable NSS certificate database                              |
| `ca-private`     | `/run/iron-proxy` (gateway)                   | CA signing key and certificate                                          |
| `ca-public`      | `/etc/ssl/certs`                              | public system roots and proxy CA; regenerated by `ca-init`               |

None of them bind to a host folder by default. `pi-workspace` is a named volume, not `./workspace`. To work on a host
folder instead, replace the `pi-workspace` mount in `docker-compose.yml` with a bind mount, and make it writable by
the app's user:

```
    volumes:
      - *ca-certs
      - pi-home:/home/nonroot
      - pi-data:/home/nonroot/.pi
      - pi-pocket-data:/home/nonroot/.pi-pocket
      - ./workspace:/workspace
```

```bash
mkdir -p workspace && sudo chown -R 65532:65532 workspace
```

Copy files out of the workspace volume, or back in:

```bash
docker compose cp app:/workspace/. ./workspace/
docker compose cp ./workspace/. app:/workspace/
```

## Security

- **The browser endpoint has no authentication.** Anyone who can reach port 9222 controls the browser and can read
  every page's cookies and files. It stays on `internal`, and port 9222 is not published.
- **Lancet Guard is off.** The compose sets `PI_POCKET_GUARD=off`. Remove the line to turn the guard on, and
  allowlist any host it needs.
- **Read-only root filesystem.** Every service uses `read_only: true`, drops capabilities, and uses
  `no-new-privileges`. The one-shot `ca-init` runs as root with only `CHOWN` added back, to make its private volume
  readable by the unprivileged gateway. The gateway sets the network-namespace `ip_unprivileged_port_start` to 0 so
  its non-root process can listen on ports 53, 80 and 443 without `NET_BIND_SERVICE`.
- **TLS interception.** Services trust the local proxy CA at runtime. Only `ca-init` and `gateway` mount its private
  key; rotate it if compromised.
- **Default-deny egress.** A process that escapes the app or `agent` still cannot reach the internet except
  through the allowlisted proxy.
- **Shared agent access.** `agent` can run commands against the shared workspace and read the shared home volume
  (including SSH keys) and Pi sign-ins. Use it only with work and credentials you intend it to access.
- **The sign-in link is in the logs.** `docker compose logs app` prints the owner's sign-in link. Keep it private,
  as you would on the host.

## Operations

```bash
docker compose up -d --build      # build images and initialize the CA before starting services
docker compose logs -f app        # watch, and read the sign-in link
docker compose ps                 # gateway health, including DNS
docker compose down               # stop; the volumes stay
docker compose down -v            # stop and delete the volumes too
```

`ca-init` must complete and `gateway` must pass its DNS and HTTP healthcheck before `app`, `chrome`, or `agent`
starts. The launcher prints the address it detects inside the container; open the published one instead:
`http://localhost:8787` on the Docker host,
or `http://<host>:8787` from the network.

To check service-name resolution, DNS interception, allowed GitHub HTTPS, and rejected HTTP(S) requests against a
running stack, run `sh tests/iron-proxy-dns.sh`. It starts the optional agent image and needs access to GitHub.
For a host-side test without containers, set `IRON_PROXY_BIN` to the verified v0.56.0 release binary and run
`sh tests/iron-proxy-local.sh`; this checks the proxy config, DNS, direct HTTPS, and the explicit proxy.

## Caveats

- The runtime must permit the gateway's namespaced `net.ipv4.ip_unprivileged_port_start` sysctl. Verify this and
  internal service-name resolution with your Podman Compose provider; behavior may differ from Docker Compose.
- Iron-proxy is pinned to version 0.56.0 and its multi-architecture image digest. The Chrome base image and other
  third-party images are not all pinned; pin them too for a fully reproducible deployment.
- The app image installs `git`, `ca-certificates`, `ripgrep`, and `fd-find` on a Debian base, so Pi's shell tools
  work. It does not install a browser: that is the `chrome` service.
- The app runs with `PI_OFFLINE=1` and `PI_TELEMETRY=0` — no version checks or telemetry.
- `chrome` is capped at 2 GB of memory, 1 GB of shared memory, and 256 processes. Lower `shm_size` only together
  with `--disable-dev-shm-usage`.
