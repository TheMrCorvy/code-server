# code-server — Quickstart & Troubleshooting Guide

> **Environment**: Intel 2018 Mac Mini · macOS Sequoia · OrbStack · code-server 4.102.x

---

## Architecture at a glance

```
Browser
  └── code-server (OrbStack container, Linux/amd64)
        ├── /host          → entire Mac Mini filesystem (read/write)
        ├── /home/coder/.ssh/id_ed25519  → ./secrets/ssh_host_key (read-only)
        └── terminal tab → /usr/local/bin/ssh-to-host-exec
                              └── ssh → host.docker.internal:22
                                    └── native macOS zsh on the Mac Mini
```

Every terminal tab in code-server SSHes into the real Mac Mini, giving you
access to `brew`, `node`, `php`, `agy`, `claude`, and every other host tool —
without duplicating anything inside Docker.

---

## One-time setup (do this once, ever)

### 1. Clone the repo and copy the env file

```bash
git clone <your-repo-url>
cd code-server
cp .env.example .env
```

### 2. Generate the SSH key pair

Run this **from inside the repo root** (not from `~`):

```bash
ssh-keygen -t ed25519 -C "code-server-container" -f ./secrets/ssh_host_key -N ""
```

> ⚠️ **Common mistake**: Running this from `~` instead of the repo root causes
> `failed: No such file or directory`. Always `cd` into the repo first.

> ⚠️ **Second common mistake**: If Docker was started before the key was
> generated, it creates a *directory* named `ssh_host_key` instead of a file.
> If you see `"Is a directory"` from ssh-keygen, fix it with:
> ```bash
> rm -rf ./secrets/ssh_host_key
> ssh-keygen -t ed25519 -C "code-server-container" -f ./secrets/ssh_host_key -N ""
> ```

### 3. Authorize the key on the host

```bash
cat ./secrets/ssh_host_key.pub >> ~/.ssh/authorized_keys
chmod 600 ~/.ssh/authorized_keys
chmod 600 ./secrets/ssh_host_key
```

### 4. Enable Remote Login on macOS

**Via GUI** (recommended — avoids permission issues):
1. **Apple menu → System Settings → General → Sharing**
2. Toggle **Remote Login** → **ON**
3. Set "Allow access for" → **All users**

**Via CLI** (requires Full Disk Access granted to your terminal app first):
```bash
sudo systemsetup -setremotelogin on
```

> ⚠️ On macOS Sequoia, `systemsetup -setremotelogin` fails with
> *"requires Full Disk Access privileges"* even with `sudo`. Use the GUI
> method above, or go to **System Settings → Privacy & Security → Full Disk
> Access** and add your terminal app before retrying.

Verify SSH is listening:
```bash
sudo lsof -i :22 | grep LISTEN
```

### 5. Fill in `.env`

Open `.env` and set at minimum:

```env
SSH_USER=your_actual_macos_username   # run `whoami` to confirm
SSH_HOST=host.docker.internal         # OrbStack resolves this automatically
SSH_PORT=22
```

`DEFAULT_WORKSPACE` is derived automatically from `SSH_USER` in
`docker-compose.yml` — it maps to `~/Desktop/www` on the Mac Mini. No need
to set it in `.env`.

### 6. Make sure `~/Desktop/www` exists

```bash
mkdir -p ~/Desktop/www
```

### 7. Start the container

```bash
docker compose up -d
docker compose logs -f code-server
```

**Expected healthy log output (first run):**
```
[entrypoint] SSH key found — host permissions apply (ensure host file is chmod 600).
[entrypoint] SSH client config written.
[entrypoint] First run — copying default VS Code settings...
[entrypoint] First run — installing VS Code extensions...
[entrypoint] Extension installation complete.
[entrypoint] Starting code-server...
[info] HTTP server listening on http://0.0.0.0:8080/
```

---

## Daily startup (container already configured)

OrbStack starts on login and respects `restart: unless-stopped`, so the
container comes back automatically after a reboot — **you usually don't need
to do anything**.

To manually start/stop:

```bash
docker compose up -d          # start
docker compose stop           # stop (keeps data)
docker compose down           # stop + remove container (keeps volumes)
```

Check status:
```bash
docker compose ps
docker compose logs --tail=50 code-server
```

---

## Using code-server

- **Default workspace**: `~/Desktop/www` (the Mac Mini host folder, via `/host`)
- **Default terminal profile**: `SSH → Host` — opens a native macOS shell
- **Container shell** (for Docker ops): click `+` in the terminal panel → **bash (container)**

---

## Installing extensions

### Open VSX extensions (auto-install supported)

Add extension IDs to the `EXTENSIONS` array in `scripts/entrypoint.sh`, then
delete the sentinel file and restart:

```bash
rm ./data/config/.extensions_initialized
docker compose restart code-server
```

### GitHub Copilot (manual install required)

`github.copilot` and `github.copilot-chat` are **proprietary Microsoft
extensions** — they are not on Open VSX Registry (code-server's default
marketplace) and cannot be auto-installed.

Install manually after opening code-server in the browser:

1. Open the **Extensions** panel (`⇧⌘X`)
2. Click `...` → **Install from VSIX…** (if you have the `.vsix` file)
   — OR —
3. Click the **Accounts** icon (bottom-left) → **Sign in with GitHub**,
   then search for **GitHub Copilot** — it appears in the built-in search
   once authenticated.

---

## Troubleshooting

### `chmod: changing permissions of '/home/coder/.ssh/id_ed25519': Read-only file system`

The SSH key is mounted `:ro` — `chmod` on a read-only bind-mount always fails
with `EROFS`, even as root. The script handles this gracefully with `|| true`.
What matters is that the **host file** has `600` permissions:

```bash
chmod 600 ./secrets/ssh_host_key
```

Then restart the container. No rebuild needed.

### Container exits immediately with code 1 (restart loop)

Check the logs for the actual error:
```bash
docker compose logs --tail=30 code-server
```

Most common cause: a command in `entrypoint.sh` failed and `set -euo pipefail`
aborted the script. Fix the underlying issue, then:
```bash
docker compose up -d
```

### `ssh-to-host` — "Permission denied (publickey)"

The host isn't accepting the key. Check:
```bash
# Confirm the public key is in authorized_keys on the host
cat ~/.ssh/authorized_keys

# Confirm permissions
ls -la ~/.ssh/authorized_keys   # must be 600
ls -la ./secrets/ssh_host_key   # must be 600

# Check sshd accepts public key auth
sudo grep PubkeyAuthentication /etc/ssh/sshd_config
# Should be: PubkeyAuthentication yes  (or absent — defaults to yes)
```

### `ssh-to-host` — "Connection refused"

SSH is not enabled on the host:
```bash
sudo systemsetup -setremotelogin on
# OR enable via System Settings → General → Sharing → Remote Login
```

### Terminal opens container bash instead of `SSH → Host`

Your `settings.json` was written before the terminal profile was configured
and won't be overwritten automatically (first-run protection). Delete it and
restart:

```bash
rm ./data/config/User/settings.json
docker compose restart code-server
```

### `host.docker.internal` doesn't resolve

OrbStack resolves this automatically. If it ever fails, verify inside the container:
```bash
docker exec -it code-server cat /etc/hosts | grep host.docker.internal
```

If missing, recreate the container:
```bash
docker compose down && docker compose up -d
```

### Extension auto-install says "not found"

The extension is not on Open VSX Registry. Install it manually via the
Extensions panel — see [GitHub Copilot](#github-copilot-manual-install-required) above.

---

## Updating code-server

Edit `CODE_SERVER_VERSION` in `.env`, then:

```bash
./scripts/update.sh <new-version>
# e.g.: ./scripts/update.sh 4.103.0
```

---

## Key file locations

| Purpose | Path |
|---|---|
| SSH private key | `./secrets/ssh_host_key` |
| SSH public key | `./secrets/ssh_host_key.pub` |
| VS Code settings | `./data/config/User/settings.json` |
| Extensions | `./data/config/extensions/` |
| Extension sentinel | `./data/config/.extensions_initialized` |
| Entrypoint script | `./scripts/entrypoint.sh` |
| SSH-to-host script | `./scripts/ssh-to-host.sh` |
| Default VS Code settings | `./config/settings.json` |
| SSH setup guide (detailed) | `./docs/ssh-setup-guide.md` |
