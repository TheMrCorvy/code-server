# SSH → Host Terminal Setup Guide

> **Goal**: Every terminal tab in code-server opens a real native shell on the host machine (macOS Sequoia or Ubuntu Server 24.04), giving you access to `brew`, `node`, `php`, `agy`, `claude`, and every other tool already installed on the host — without duplicating dependencies inside Docker.

---

## How it works (architecture overview)

```
Browser
  └── code-server (Docker container, Linux)
        └── terminal tab runs: /usr/local/bin/ssh-to-host
              └── ssh → host.docker.internal:22
                    └── real shell on macOS / Ubuntu
```

The container connects to the host over Docker's internal virtual network. The packet never leaves the machine — no internet hop, no public exposure.

---

## Prerequisites checklist

- [ ] OrbStack (macOS) or Docker Engine (Ubuntu) running
- [ ] `./secrets/ssh_host_key` created (Step 2 below)
- [ ] `.env` filled in with `SSH_USER`, `SSH_HOST`, `SSH_PORT` (Step 3)
- [ ] Public key added to host `~/.ssh/authorized_keys` (Step 4)
- [ ] SSH enabled on the host OS (Step 5)

---

## Step 1 — Clone and prepare the repo

If you haven't already:

```bash
git clone <your-repo-url>
cd code-server
cp .env.example .env
```

---

## Step 2 — Generate the SSH key pair

Generate a dedicated Ed25519 key pair specifically for this container. Do this **on any machine** (your laptop, the Mac Mini itself — anywhere with `ssh-keygen`).

```bash
# Run this wherever you are comfortable generating keys
ssh-keygen -t ed25519 -C "code-server-container" -f ./secrets/ssh_host_key -N ""
```

This creates two files:

| File | Purpose | Git status |
|---|---|---|
| `secrets/ssh_host_key` | **Private key** — stays in the repo folder, mounted into container | Gitignored |
| `secrets/ssh_host_key.pub` | **Public key** — you will paste this into the host's authorized_keys | Gitignored |

> [!CAUTION]
> Never commit `secrets/ssh_host_key` (the private key) to git. The `.gitignore` already blocks this, but always double-check before pushing.

Print the public key — you'll need it in Step 4:

```bash
cat secrets/ssh_host_key.pub
```

---

## Step 3 — Fill in `.env`

Open `.env` and set the SSH section:

```env
SSH_USER=your_actual_username   # run `whoami` on the host to find this
SSH_HOST=host.docker.internal   # works on both macOS (OrbStack/DD) and Ubuntu
SSH_PORT=22                      # change only if you moved the SSH port
```

> [!TIP]
> OrbStack users can also use `host.orb.internal` for `SSH_HOST`. Both resolve to the same place; `host.docker.internal` is more portable.

---

## Step 4 — Add the public key to the host

### macOS Sequoia

```bash
# On the Mac Mini (in any terminal):
mkdir -p ~/.ssh
chmod 700 ~/.ssh

# Paste the content of secrets/ssh_host_key.pub here:
echo "ssh-ed25519 AAAA...your-public-key... code-server-container" >> ~/.ssh/authorized_keys

chmod 600 ~/.ssh/authorized_keys
```

Verify:
```bash
cat ~/.ssh/authorized_keys
# Should show the key you just added
```

### Ubuntu Server 24.04

```bash
# On the Ubuntu server:
mkdir -p ~/.ssh
chmod 700 ~/.ssh

echo "ssh-ed25519 AAAA...your-public-key... code-server-container" >> ~/.ssh/authorized_keys

chmod 600 ~/.ssh/authorized_keys
```

---

## Step 5 — Enable SSH on the host OS

### macOS Sequoia

1. Open **System Settings**
2. Go to **General → Sharing**
3. Enable **Remote Login**
4. Under "Allow access for", choose **All users** or add your user specifically

Verify from any terminal on the Mac:
```bash
sudo systemsetup -getremotelogin
# Output: Remote Login: On
```

Or enable via CLI directly:
```bash
sudo systemsetup -setremotelogin on
```

Verify the SSH daemon is listening:
```bash
sudo lsof -i :22 | grep ssh
```

### Ubuntu Server 24.04

```bash
# Install and enable OpenSSH server
sudo apt update
sudo apt install -y openssh-server

# Start now and enable on boot
sudo systemctl enable --now ssh

# Check status
sudo systemctl status ssh
```

Allow SSH through the firewall:
```bash
sudo ufw allow ssh     # or: sudo ufw allow 22/tcp
sudo ufw reload
sudo ufw status
```

Verify it's listening:
```bash
ss -tlnp | grep :22
```

---

## Step 6 — Start (or restart) the container

```bash
# First time
docker compose up -d

# Already running — apply .env and volume changes
docker compose restart code-server

# Check logs to confirm SSH setup ran correctly
docker compose logs code-server | grep -E "\[entrypoint\] SSH"
```

Expected log output:
```
[entrypoint] SSH key found — permissions set (600).
[entrypoint] SSH client config written.
```

If you see `WARNING: SSH key not found`, go back to Step 2.

---

## Step 7 — Test the connection

Open a terminal in code-server. You should see:

```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  code-server  ›  Host Terminal
  youruser@host.docker.internal:22
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

Then your actual host shell prompt appears. Verify you're on the real machine:

```bash
whoami        # your real username
which brew    # /opt/homebrew/bin/brew  (macOS) or not found (Ubuntu)
which node    # your real node install
agy --version # your real agy install
```

To open a container shell (for Docker-specific operations), click the `+` dropdown in the terminal panel and choose **bash (container)**.

---

## Step 8 — On-boot persistence

### macOS Sequoia (OrbStack)

OrbStack starts on login by default and respects `restart: unless-stopped`. Your container will restart automatically after a reboot **as long as auto-login is enabled** (OrbStack needs a logged-in user to run):

> System Settings → Users & Groups → Automatically log in as → your user

### Ubuntu Server 24.04

Docker's systemd service starts automatically at boot. The container starts because of `restart: unless-stopped`. No extra config needed.

```bash
# Verify Docker is boot-enabled
sudo systemctl is-enabled docker   # should output: enabled

# Verify container recovers after reboot
docker compose ps
```

---

## Troubleshooting

### "Permission denied (publickey)"

The host doesn't accept the key. Verify:
```bash
# From inside the container terminal (bash (container) profile)
cat /home/coder/.ssh/id_ed25519.pub
# Should match a line in ~/.ssh/authorized_keys on the host
```

Check host `authorized_keys` permissions:
```bash
# On the host
ls -la ~/.ssh/authorized_keys   # must be -rw------- (600)
```

Check the sshd config allows public key auth:
```bash
# macOS / Ubuntu
sudo grep -E "PubkeyAuthentication|AuthorizedKeysFile" /etc/ssh/sshd_config
# PubkeyAuthentication yes  (or absent — defaults to yes)
```

### "Connection refused" on macOS

SSH is not enabled:
```bash
sudo systemsetup -setremotelogin on
```

### "Connection refused" on Ubuntu

The SSH service isn't running:
```bash
sudo systemctl start ssh
sudo systemctl enable ssh
```

### `host.docker.internal` doesn't resolve

On Ubuntu, the `extra_hosts` entry in `docker-compose.yml` injects this automatically. Verify it resolved:
```bash
# From inside the container (bash (container) profile)
cat /etc/hosts | grep host.docker.internal
# Should show: 192.168.x.x  host.docker.internal
```

If the line is missing, recreate the container:
```bash
docker compose down && docker compose up -d
```

### Terminal opens container bash instead of SSH

Your existing `settings.json` was written before this change and won't be overwritten automatically (first-run protection). Delete it and restart:

```bash
# On the host, from the repo root
rm ./data/config/User/settings.json
docker compose restart code-server
```

---

## Security notes

- `secrets/ssh_host_key` is a **host-local** private key — it never leaves your machine unless you explicitly copy it.
- The SSH connection travels only through Docker's internal virtual network — it never touches the internet.
- `StrictHostKeyChecking=accept-new` trusts the host fingerprint on first connect and remembers it permanently. Correct for a trusted local setup.
- `ForwardAgent no` is intentional — agent forwarding would let a compromised container leverage your other SSH keys.
