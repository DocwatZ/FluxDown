---
title: Docker & NAS
description: Run the headless FluxDown server from the prebuilt Docker image, with Docker Compose, CasaOS/ZimaOS, and Unraid.
section: headless-server
order: 2
---

The fastest way to run the headless server is the prebuilt Docker image — no Cargo build, no separate Web UI build step. The image bundles the server binary and the Web UI, exposes everything on one port (`17800`), and persists its database, logs, and access token to a volume.

Image: `ghcr.io/zerx-lab/fluxdown-server` (tags: a specific version like `0.1.54`, or `latest`).

> Prefer a pinned version tag over `latest` for reproducible deployments.

## docker run

```bash
docker run -d \
  --name fluxdown-server \
  --restart unless-stopped \
  -p 17800:17800 \
  -v fluxdown-data:/data \
  -v /path/to/downloads:/root/Downloads \
  ghcr.io/zerx-lab/fluxdown-server:latest
```

- `/data` holds the database, logs, and the generated admin token — keep it on a persistent volume.
- `/root/Downloads` is the container's default download directory (`HOME=/root`); bind it to a host path you want files written to.

The admin token is generated once on first launch and printed to the container log. Capture it:

```bash
docker logs fluxdown-server 2>&1 | grep -i token
```

Use it to sign in to the Web UI and to authenticate the management API and MCP endpoint (`Authorization: Bearer <token>`).

## Docker Compose

```yaml
services:
  fluxdown-server:
    image: ghcr.io/zerx-lab/fluxdown-server:latest
    container_name: fluxdown-server
    restart: unless-stopped
    ports:
      - "17800:17800"
    volumes:
      - fluxdown-data:/data
      - ./downloads:/root/Downloads
    # environment:
    #   FLUXDOWN_LANG: zh
    #   FLUXDOWN_DATABASE_URL: postgres://user:pass@host:5432/fluxdown

volumes:
  fluxdown-data:
```

```bash
docker compose up -d
docker compose logs fluxdown-server 2>&1 | grep -i token
```

All environment variables from [Server Setup](/docs/en/headless-server/setup/) apply — most usefully `FLUXDOWN_LANG` (default Web UI language, `en`/`zh`) and `FLUXDOWN_DATABASE_URL` (point at an external PostgreSQL instead of the bundled SQLite).

## CasaOS / ZimaOS

FluxDown is published as a third-party CasaOS / ZimaOS app store, so you can install it with one click.

In CasaOS / ZimaOS: **App Store → Sources → Add**, then enter:

```
https://cdn.jsdelivr.net/gh/zerx-lab/casaos-appstore@gh-pages
```

Then install **FluxDown** from the store. Store source: [zerx-lab/casaos-appstore](https://github.com/zerx-lab/casaos-appstore).

## Unraid

FluxDown is available in Unraid's **Community Applications** (CA) plugin. No manual Docker command needed — CA handles the template, pulls the image, and wires up the paths for you.

### Prerequisites

- Unraid 6.9 or later
- **Community Applications** plugin installed (Apps tab visible in the Unraid WebUI)

### Step 1 — Find FluxDown in Community Applications

1. In the Unraid WebUI, click the **Apps** tab.
2. In the search box, type **FluxDown**.
3. Click the **FluxDown** card (published by *zerx-lab*).

> **Can't find it?** The CA template lives in [zerx-lab/unraid-templates](https://github.com/zerx-lab/unraid-templates). If your CA index hasn't refreshed yet, click **Apps → settings → Force update of all repository lists**, then search again.

### Step 2 — Configure the template

The template fields you'll most likely want to adjust before clicking **Apply**:

| Field | Default | Recommended |
|---|---|---|
| **WebUI Port** | `17800` | Keep as-is, or change if `17800` is already in use on your server. |
| **Data directory** (AppData path) | `/mnt/user/appdata/fluxdown/data` | Keep as-is, or point to your preferred AppData share. This folder holds the database, logs, and the generated admin token — keep it on a persistent path. |
| **Downloads directory** | `/mnt/user/downloads` | Point to whatever share you want finished files to land in. Unraid share names are case-sensitive — use the exact name of your share (e.g. `/mnt/user/downloads` or `/mnt/user/Downloads` depending on how you named it). |
| **Timezone (`TZ`)** | `Etc/UTC` | Set to your local timezone (e.g. `America/New_York`, `Europe/London`, `Asia/Shanghai`). |

All other fields can stay at their defaults for a first install.

### Step 3 — Apply and let it pull

Click **Apply**. Unraid pulls the image (`ghcr.io/zerx-lab/fluxdown-server:latest`) and starts the container. This may take a minute on first run depending on your internet speed.

### Step 4 — Grab the admin token

The very first time the container starts, it generates a one-time admin token and prints it to the container log. Retrieve it before you close the Unraid UI:

1. In the Unraid WebUI, go to **Docker** tab.
2. Click the FluxDown container row to expand it, then click **Logs** (or use the terminal icon).
3. Look for a banner that contains your token:

   ```
   ==============================================================
     FluxDown Server first run — admin token generated:
       fxd_1a2b3c4d5e6f7890a1b2c3d4e5f67890
     Use it to sign in to the Web UI and the management API.
   ==============================================================
   ```

   Or grab it with a one-liner in the Unraid terminal:

   ```bash
   docker logs fluxdown-server 2>&1 | grep -i token
   ```

4. **Copy and save this token.** It is only printed once. If you lose it:
   - **If you can still log in** (e.g. using another session): regenerate it from **Web UI → Settings → Security & Access → Access Token → Regenerate**.
   - **If you are locked out**: stop the container, delete the `admin_token` row from the `config` table in the SQLite database (located in your AppData `/data` volume), then restart the container — a fresh token will be printed to the log on the next startup.

### Step 5 — Open the Web UI

Navigate to:

```
http://[UNRAID-SERVER-IP]:17800
```

Enter the token from Step 4 on the login screen. You're in — create your first download task from **+ New Download** in the top bar.

### Updating FluxDown on Unraid

When a new version is released, update via the **Docker** tab the same way you update any other container:

- **Manual** — Click the container row → **Force Update** (or the update arrow if CA shows a badge).
- **Auto-updates** — Enable in **Docker** tab settings if you prefer hands-off upgrades.

The `/data` volume is separate from the image, so your tasks, settings, and token survive the update.


## Podman

Podman is a drop-in Docker alternative that runs without a daemon.  Replace every `docker` command with `podman`; the image, flags, and volume paths are identical.

One important difference: Podman's rootless mode maps the host user to UID 0 **inside** the container by default, which can cause PUID/PGID mismatch.  Add `--userns=keep-id` so that your host user's UID/GID are preserved inside the container:

```bash
podman run -d \
  --name fluxdown-server \
  --userns=keep-id \
  -e PUID=1000 \
  -e PGID=1000 \
  -e FLUXDOWN_DOWNLOAD_DIR=/downloads \
  -v /path/to/data:/data \
  -v /path/to/downloads:/downloads \
  -p 17800:17800 \
  ghcr.io/docwatz/fluxdown-server:latest
```

For a systemd quadlet (rootless, auto-start on login):

```ini
# ~/.config/containers/systemd/fluxdown.container
[Unit]
Description=FluxDown Server

[Container]
Image=ghcr.io/docwatz/fluxdown-server:latest
UserNS=keep-id
Environment=PUID=1000
Environment=PGID=1000
Environment=FLUXDOWN_DOWNLOAD_DIR=/downloads
Volume=/path/to/data:/data:Z
Volume=/path/to/downloads:/downloads:Z
PublishPort=17800:17800

[Install]
WantedBy=default.target
```

---

## Synology (Container Manager)

Synology DSM 7.2+ ships **Container Manager**, which replaces Docker for Synology.  Community Applications are not available; use the GUI instead.

1. Open **Container Manager → Registry** and search for **fluxdown-server** (`ghcr.io/docwatz/fluxdown-server`).  Download the `latest` tag.
2. Go to **Container → Create** and select the downloaded image.
3. On the **Port Settings** tab, map **Local Port 17800 → Container Port 17800** (TCP).
4. On the **Volume Settings** tab, add two bindings:
   - `/volume1/docker/fluxdown/data` → `/data`
   - `/volume1/docker/fluxdown/downloads` → `/downloads` (or whichever shared folder you want to download into)
5. On the **Environment** tab, add:
   | Variable | Value |
   |---|---|
   | `PUID` | Your DSM user's UID (find with `id` in SSH) |
   | `PGID` | Your DSM user's GID |
   | `FLUXDOWN_DOWNLOAD_DIR` | `/downloads` |
   | `FLUXDOWN_TOKEN` | *(optional)* pre-set your admin token |
6. Click **Apply** / **Done**.  The container starts automatically.

> **Permissions:** The `/volume1/docker/fluxdown/data` and `/downloads` folders must be owned by (or at minimum writable by) the UID/GID you set in Step 5.  Use **File Station** or SSH `chown` to fix ownership if the container fails to start.

---

## TrueNAS SCALE

TrueNAS SCALE can run FluxDown either as a **Custom App** (straightforward) or through the **Community Apps catalogue** if a chart is available.

### Custom App (recommended)

1. In the TrueNAS web UI, go to **Apps → Discover Apps → Custom App**.
2. Set the image to `ghcr.io/docwatz/fluxdown-server` with tag `latest`.
3. Under **Port Forwarding**, add `17800:17800` (TCP).
4. Under **Storage**, add two **Host Path** volumes:
   - `/mnt/pool/fluxdown/data` → `/data`
   - `/mnt/pool/fluxdown/downloads` → `/downloads`
5. Under **Environment Variables**, add:
   | Name | Value |
   |---|---|
   | `PUID` | `568` (TrueNAS apps default) or your preferred UID |
   | `PGID` | `568` |
   | `FLUXDOWN_DOWNLOAD_DIR` | `/downloads` |
6. Click **Save**.

> **Dataset permissions:** Create the `data` and `downloads` datasets before deploying and set their owner to UID/GID `568` (or whichever IDs you chose) via **Datasets → Permissions → Edit** → Unix Permissions.

### Community Apps catalogue

If a FluxDown chart is published to the [TrueCharts](https://truecharts.org) or iXsystems community catalogue, install it from **Apps → Discover Apps** by searching for "FluxDown".  The chart pre-configures all the volume mounts and environment variables; just review the defaults and click **Install**.

---

## Exposing it safely

The image binds `0.0.0.0:17800` inside the container, mapped to the host. As with any headless deployment, the admin token is the only thing guarding full remote control — see the [reverse proxy & TLS guidance](/docs/en/headless-server/setup/) before exposing it beyond a trusted LAN.

## Next steps

- [Web UI](/docs/en/headless-server/web-ui/) — sign in and manage downloads from a browser.
- [API Overview](/docs/en/api/overview/) — automate the server from scripts or other tools.
