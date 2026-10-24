# Pi Pocket Docker

Docker Compose deployment for Pi Pocket. The application source is pinned as a Git submodule at `src/`.

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

Open <http://localhost:8787> on the Docker host. See [docker/README.md](docker/README.md) for requirements, network layout, allowlist configuration, persistent volumes, and operations.

The app image copies its source from `src/`. To change the Pi Pocket revision used by the deployment, update the `src` submodule and commit its new pointer.
