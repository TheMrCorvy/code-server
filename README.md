# 🖥️ code-server — Homelab IDE

> Browser-based VS Code for your homelab. Deploy with Docker, expose securely via [Pangolin](https://github.com/fosrl/pangolin) + Newt, and upgrade to Kubernetes whenever you're ready.

---

## 📁 Repository Structure

```
code-server/
├── Dockerfile                  # Custom image: base + Node.js LTS, PHP 8, Composer
├── docker-compose.yml          # Primary deployment
├── .env.example                # Environment variable template → copy to .env
├── .gitignore
├── config/
│   └── settings.json           # Default VS Code settings (seeded on first run)
├── scripts/
│   ├── entrypoint.sh           # Container bootstrap: seeds settings & installs extensions
│   └── update.sh               # Helper to update code-server to a newer version
└── k8s/                        # Kubernetes manifests (future migration)
    ├── kustomization.yaml
    ├── namespace.yaml
    ├── secret.yaml
    ├── pvc.yaml
    ├── deployment.yaml
    ├── service.yaml
    └── ingress.yaml
```

---

## 🚀 Deployment

### Prerequisites

- [Docker](https://docs.docker.com/engine/install/) and the [Compose plugin](https://docs.docker.com/compose/install/) installed on the host machine.

### 1. Clone the repository

```bash
git clone <your-repo-url> code-server
cd code-server
```

### 2. Create your `.env` file

```bash
cp .env.example .env
```

Open `.env`. The only value you **must** change before the first run is `TZ` if the pre-set timezone (`America/Argentina/Buenos_Aires`) does not match yours. Authentication is disabled by default (`AUTH=none`) because Pangolin SSO handles it.

```bash
# Minimum change required if your timezone differs:
TZ=Europe/London
```

Everything else has working defaults.

### 3. Build and start

```bash
docker compose up -d --build
```

The `--build` flag is only needed on the first run and after any change to the `Dockerfile`. After that, `docker compose up -d` is enough.

> **First-run note:** `scripts/entrypoint.sh` installs all VS Code extensions into the persistent volume automatically. This takes 2–4 minutes. Follow progress with:
>
> ```bash
> docker compose logs -f code-server
> ```

### 4. Access

Open **[http://localhost:8080](http://localhost:8080)** — no password prompt, Pangolin SSO handles authentication.

---

## ⚙️ How It Works

```
docker compose up --build
       │
       ▼
  Dockerfile builds the image
  (adds Node.js LTS, PHP 8, Composer on top of the official code-server base)
       │
       ▼
  scripts/entrypoint.sh runs on every container start
       ├── Creates ./data/ subdirectories if the volume is empty
       ├── Seeds config/settings.json into the volume (first run only)
       ├── Installs all VS Code extensions into the volume (first run only)
       └── exec code-server --bind-addr 0.0.0.0:8080 --auth none ...
```

Extensions, settings, and your projects all live under `./data/` on the host and survive container restarts and image rebuilds completely intact.

---

## 🔧 Configuration Reference

All options are in `.env`:

| Variable              | Default                          | Description                                                                              |
| --------------------- | -------------------------------- | ---------------------------------------------------------------------------------------- |
| `CODE_SERVER_VERSION` | `4.102.1`                        | Image version. Change and rebuild to upgrade.                                            |
| `AUTH`                | `none`                           | `none` = no login screen (use behind Pangolin SSO). `password` = enable built-in prompt. |
| `PASSWORD`            | —                                | Only used when `AUTH=password`.                                                          |
| `HASHED_PASSWORD`     | —                                | SHA-256 hash alternative to `PASSWORD`. Overrides it when set.                           |
| `DATA_DIR`            | `./data`                         | Host path for all persistent data.                                                       |
| `DEFAULT_WORKSPACE`   | `/home/coder/projects`           | Folder opened in the editor on startup.                                                  |
| `PROXY_DOMAIN`        | _(empty)_                        | Public domain assigned by Pangolin (e.g. `code.yourdomain.com`).                         |
| `TZ`                  | `America/Argentina/Buenos_Aires` | Container timezone.                                                                      |
| `DOCKER_GID`          | —                                | Host Docker group GID. Needed for Docker socket access from the terminal.                |

---

## ⬆️ Updating code-server

```bash
# Update to a specific version
bash scripts/update.sh 4.200.0

# Resolve and apply the latest release automatically (requires jq)
bash scripts/update.sh latest
```

The script updates `CODE_SERVER_VERSION` in `.env`, rebuilds the image with `--no-cache`, and restarts the container. Your extensions and settings in `./data/` are untouched.

Check all available versions: https://github.com/coder/code-server/releases

---

## 🤖 GitHub Copilot

Copilot is installed automatically on first run. Because code-server runs in a browser rather than the native VS Code app, authentication uses the OAuth **Device Flow**:

1. Press `Ctrl+Shift+P` → **"GitHub Copilot: Sign In"**
2. Copy the 8-character device code shown in the popup
3. Visit **https://github.com/login/device** and enter the code
4. Authorize the app — Copilot activates in the status bar

> [!NOTE]
> Copilot requires a secure context. It authenticates over `localhost` or `https://` but will refuse plain `http://` on a remote domain. Ensure your Pangolin domain uses HTTPS.

---

## 🧩 Pre-installed Extensions

Only the two extensions required for GitHub Copilot are installed automatically on first run:

- `github.copilot` — AI code completion
- `github.copilot-chat` — AI chat assistant

Any additional extensions can be installed manually from the Extensions panel inside code-server.

To add extensions, edit the `EXTENSIONS` array in `scripts/entrypoint.sh`. To force a reinstall of all extensions, delete the sentinel file and restart:

```bash
rm ./data/config/.extensions_initialized
docker compose restart code-server
```

---

## 🐳 Useful Commands

```bash
# Follow logs (useful during first-run extension install)
docker compose logs -f code-server

# Open a shell inside the container
docker compose exec code-server bash

# Stop the container
docker compose down

# Full restart
docker compose restart code-server

# Check resource usage
docker stats code-server
```

---

## ☸️ Kubernetes (Future Migration)

All manifests are in `k8s/`. See the comments inside each file for configuration notes. Apply everything at once with:

```bash
kubectl apply -k k8s/
```

Port-forward to test locally before configuring an Ingress:

```bash
kubectl port-forward -n code-server svc/code-server 8080:80
```

---

## 🔒 Security Notes

- Port `8080` is bound to `127.0.0.1` — not reachable from the network. Only Pangolin (running on the same host) can connect.
- The container runs as the unprivileged `coder` user (UID 1000).
- `no-new-privileges` is enforced.
- `AUTH=none` is safe **only** because the port is localhost-only and Pangolin SSO gates access.

---

## 🛠️ Troubleshooting

| Symptom                                 | Fix                                                                         |
| --------------------------------------- | --------------------------------------------------------------------------- |
| Container won't start                   | `docker compose logs code-server`                                           |
| Editor stuck on "Loading…"              | WebSocket support missing in Pangolin config                                |
| Copilot won't authenticate              | Must be on HTTPS or localhost. Use Device Flow above.                       |
| Extensions missing after restart        | They persist — check `./data/config/extensions/` exists                     |
| Extensions won't install                | Delete `./data/config/.extensions_initialized` and restart                  |
| `docker: permission denied` in terminal | Configure `DOCKER_GID` and `group_add` (see above)                          |
| Health check failing for first ~2 min   | Normal — extension install takes time. `start_period: 120s` is intentional. |
