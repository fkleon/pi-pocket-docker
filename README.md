# Pi Pocket Docker

Docker Compose deployment for Pi Pocket. The application source and MCP extension are pinned as Git submodules at
`src/pi-pocket/` and `src/pocket-mcp/`.

Clone with the submodule, then start the stack:

```bash
git clone --recurse-submodules <repository-url>
cd pi-pocket-docker
docker compose up --build
```

If you already cloned without submodules, initialize it before building:

```bash
git submodule update --init --recursive
docker compose up --build
```

Open <http://localhost:8787> on the Docker host. To run the optional Pi CLI container with the same sign-ins and
workspace, use `docker compose --profile agent run --build --rm agent`. See [docker/README.md](docker/README.md)
for requirements, network layout, allowlist configuration, persistent volumes, and operations.

The app image copies Pi Pocket from `src/pi-pocket/` and the MCP extension from `src/pocket-mcp/`. To update either revision, update that submodule and commit its new pointer.
