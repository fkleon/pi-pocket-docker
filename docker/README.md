# Running Pi Pocket with Docker Compose

`docker-compose.yml` at the repository root runs Pi Pocket with a browser of its own and gates every outbound
request through an allowlist. The app runs unprivileged on a read-only root filesystem; the browser, the MITM egress
proxy, and DNS each run in a container of their own. Only the reverse proxy is reachable from outside. A one-shot
initializer generates the egress CA on first startup and shares its public trust store through a named volume.

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
| `gateway`       | `ironsh/iron-proxy:0.56.0`           | internal, edge     | HTTP/HTTPS MITM egress proxy with a host allowlist            |
| `dns-forwarder` | `docker/dnsmasq.Dockerfile`          | internal, edge     | DNS, forwarding only the allowlisted domains                 |
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
                 │ MITM proxy :8888 / DNS :53        │ MITM proxy :8888 / DNS :53
                 ▼                                   ▼
     ┌───────────────────────┐           ┌───────────────────────┐
     │ gateway               │           │ dns-forwarder         │
     │ iron-proxy            │           │ dnsmasq .11           │
     └───────────┬───────────┘           └───────────┬───────────┘
  ───────────────┼───────────────────────────────────┼──────────────
  edge · the only network with a route to the internet
  ───────────────┼───────────────────────────────────┼──────────────
                 └────────────────┬──────────────────┘
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
| `app`           | `gateway`       | 8888 | HTTP and HTTPS proxy               |
| `app`           | `dns-forwarder` | 53   | DNS                                 |
| `agent`         | `gateway`       | 8888 | proxied model and provider requests |
| `agent`         | `dns-forwarder` | 53   | DNS                                 |
| `chrome`        | `gateway`       | 8888 | page loads                          |
| `chrome`        | `dns-forwarder` | 53   | DNS                                |
| `gateway`       | internet        | 80/443 | allowed HTTP and HTTPS upstream requests |
| `dns-forwarder` | internet        | 53   | upstream DNS for allowlisted names |

What cannot happen:

- `app`, `chrome`, and `agent` cannot reach the internet directly. They are on `internal`, which has no route out;
  their only way out is `gateway`.
- `chrome`'s DevTools port 9222 is never published, and the endpoint has no authentication.
- 8787 is the only published port, and only `ingress` is on `frontend`.

## The egress allowlist

During this first migration step, two files still gate egress, and both must allow a domain:

- `docker/dnsmasq.conf` forwards only the domains listed with `server=/example.com/#`; every other name gets
  NXDOMAIN. Subdomains are included.
- `docker/iron-proxy.yaml` contains the HTTP/S host allowlist. It initially mirrors the former Tinyproxy list; path
  and method restrictions can be added there after reviewing the actual provider requests.

The defaults allow `radius.earendil.com` (an example provider), `radius.pi.dev`, and `pi.dev`, plus the GitHub hosts
and local Git host in the config. The Iron-proxy entries intentionally preserve the former host-level policy for
this migration; all methods and paths remain allowed, and no credentials are injected yet. Replace the domains with
the ones your models use. If a provider is missing from either file, runs against it fail: DNS refuses the name, or
the proxy refuses the request.

After editing either file, recreate the services so they read the new config:

```bash
docker compose up -d --force-recreate gateway dns-forwarder
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
  readable by the unprivileged gateway. Iron-proxy listens on high ports and does not need `NET_BIND_SERVICE`.
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
docker compose ps                 # health of gateway and dns-forwarder
docker compose down               # stop; the volumes stay
docker compose down -v            # stop and delete the volumes too
```

`ca-init` must complete before the dependent services start. `gateway` and `dns-forwarder` must pass their
healthchecks before `app` starts; `chrome` waits for DNS, and `agent` waits for the gateway. The launcher prints the address it detects inside the container; open the published one
instead: `http://localhost:8787` on the Docker host,
or `http://<host>:8787` from the network.

## Caveats

- Iron-proxy is pinned to version 0.56.0 and its multi-architecture image digest. The Chrome base image and other
  third-party images are not all pinned; pin them too for a fully reproducible deployment.
- The app image installs `git`, `ca-certificates`, `ripgrep`, and `fd-find` on a Debian base, so Pi's shell tools
  work. It does not install a browser: that is the `chrome` service.
- The app runs with `PI_OFFLINE=1` and `PI_TELEMETRY=0` — no version checks or telemetry.
- `chrome` is capped at 2 GB of memory, 1 GB of shared memory, and 256 processes. Lower `shm_size` only together
  with `--disable-dev-shm-usage`.
