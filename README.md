![](.github/images/repo_header.png)

[![n8n](https://img.shields.io/badge/n8n-2.25.5-blue.svg)](https://github.com/n8n-io/n8n/releases/tag/n8n%402.25.5)
[![Dokku](https://img.shields.io/badge/Dokku-Repo-blue.svg)](https://github.com/dokku/dokku)

# Run n8n 2.x on Dokku

## Overview

n8n 2.x runs Code node execution through task runners. For production Dokku deployments, this repo deploys two Dokku apps from the same Git repository:

- `n8n`: the main n8n web UI, API, webhooks, and task broker
- `n8n-runners`: the external task runner container for JavaScript and Python Code nodes

The apps share a private Dokku network. Only the main `n8n` app is publicly exposed; the runner app connects privately to the task broker at `http://n8n.web:5679`.

Both images are pinned to the same n8n version:

- `Dockerfile` uses `n8nio/n8n:${N8N_VERSION}`
- `Dockerfile.runners` uses `n8nio/runners:${N8N_VERSION}`

The runner image preserves the custom JavaScript Code-node packages from this repo: `node-fetch`, `@paralleldrive/cuid2`, `franc`, and `@distube/ytdl-core`.

## Prerequisites

- A working [Dokku](https://dokku.com/) host
- The [dokku-postgres plugin](https://github.com/dokku/dokku-postgres)
- Dokku network support
- Optional: the [dokku-letsencrypt plugin](https://github.com/dokku/dokku-letsencrypt)

## Setup

Run these commands on your Dokku host unless noted otherwise.

### 1. Create the apps

```bash
dokku apps:create n8n
dokku apps:create n8n-runners
```

### 2. Set Dockerfile paths

Both apps build from this repo, but each app uses a different Dockerfile.

```bash
dokku builder-dockerfile:set n8n dockerfile-path Dockerfile
dokku builder-dockerfile:set n8n-runners dockerfile-path Dockerfile.runners
```

### 3. Create and link Postgres

Postgres is linked only to the main app. The runner app does not need database access.

```bash
dokku postgres:create n8n
dokku postgres:link n8n n8n
```

### 4. Create a private network

Attach both apps to the same private Dokku network so the runner can reach the broker on `n8n.web:5679`.

```bash
dokku network:create n8n-internal
dokku network:set n8n attach-post-create n8n-internal
dokku network:set n8n-runners attach-post-create n8n-internal
```

If these apps were already deployed before you changed network settings, rebuild them so the new containers join the network:

```bash
dokku ps:rebuild n8n
dokku ps:rebuild n8n-runners
```

### 5. Configure the main n8n app

Generate stable secrets from your local machine or the Dokku host:

```bash
N8N_ENCRYPTION_KEY="$(openssl rand -hex 32)"
N8N_RUNNERS_AUTH_TOKEN="$(openssl rand -hex 32)"
```

Set the main app config:

```bash
dokku config:set n8n \
  N8N_ENCRYPTION_KEY="$N8N_ENCRYPTION_KEY" \
  WEBHOOK_URL="https://n8n.example.com" \
  N8N_RUNNERS_ENABLED=true \
  N8N_RUNNERS_MODE=external \
  N8N_RUNNERS_BROKER_LISTEN_ADDRESS=0.0.0.0 \
  N8N_RUNNERS_AUTH_TOKEN="$N8N_RUNNERS_AUTH_TOKEN"
```

If you use Python Code nodes, also enable the native Python runner:

```bash
dokku config:set n8n N8N_NATIVE_PYTHON_RUNNER=true
```

Keep `N8N_ENCRYPTION_KEY` unchanged after the first deploy. Changing it can make stored credentials unreadable.

### 6. Configure the runner app

Use the same runner auth token value that you set on the main app.

```bash
dokku config:set n8n-runners \
  N8N_RUNNERS_TASK_BROKER_URI=http://n8n.web:5679 \
  N8N_RUNNERS_AUTH_TOKEN="$N8N_RUNNERS_AUTH_TOKEN"
```

### 7. Disable the runner proxy

The runner app should not be publicly exposed.

```bash
dokku proxy:disable n8n-runners
```

### 8. Configure persistent storage

Persist the main n8n data directory:

```bash
dokku storage:ensure-directory n8n --chown false
chown 1000:1000 /var/lib/dokku/data/storage/n8n
dokku storage:mount n8n /var/lib/dokku/data/storage/n8n:/home/node/.n8n
```

n8n 2.x restricts file-node access to `~/.n8n-files` by default. If your workflows read or write local files, mount that directory too:

```bash
dokku storage:ensure-directory n8n-files --chown false
chown 1000:1000 /var/lib/dokku/data/storage/n8n-files
dokku storage:mount n8n /var/lib/dokku/data/storage/n8n-files:/home/node/.n8n-files
```

### 9. Configure domains and ports

Expose only the main app:

```bash
dokku domains:set n8n n8n.example.com
dokku ports:set n8n http:80:5678
dokku ports:add n8n https:443:5678
```

If you use dokku-letsencrypt:

```bash
dokku letsencrypt:set n8n email you@example.com
dokku letsencrypt:enable n8n
```

### 10. Deploy

#### Option A: `dokku git:sync`

```bash
dokku git:sync --build n8n https://github.com/d1ceward-on-dokku/n8n_on_dokku.git
dokku git:sync --build n8n-runners https://github.com/d1ceward-on-dokku/n8n_on_dokku.git
```

#### Option B: manual Git remotes

From your local clone:

```bash
git remote add dokku-n8n dokku@example.com:n8n
git remote add dokku-n8n-runners dokku@example.com:n8n-runners

git push dokku-n8n master
git push dokku-n8n-runners master
```

## Verifying the deployment

On the Dokku host:

```bash
dokku ps:report n8n
dokku ps:report n8n-runners
dokku logs n8n --tail
dokku logs n8n-runners --tail
```

Expected checks:

- the `n8n` app boots and listens publicly on port `5678`
- the `n8n-runners` app boots without a public proxy
- runner logs show a successful connection to `http://n8n.web:5679`
- the n8n UI loads at `https://n8n.example.com`
- webhooks use the configured `WEBHOOK_URL`
- Postgres-backed data persists across main app restarts
- JavaScript Code nodes can import `node-fetch`, `@paralleldrive/cuid2`, `franc`, and `@distube/ytdl-core`

## Updating n8n

Run the `update` script from a maintainer checkout to move both Dockerfiles and the README badge to the latest stable n8n 2.x release.

```bash
./update
```

The main and runner image versions must stay synchronized.

## Migrating from n8n 1.x to 2.x

For existing deployments:

1. Upgrade your current instance to the latest n8n 1.x release first.
2. In the n8n UI, run **Settings > Migration Report**.
3. Fix critical workflow and instance issues reported by the migration tool.
4. Back up Postgres and `/home/node/.n8n`.
5. Deploy the n8n 2.x main app and the `n8n-runners` app from this repo.

Common n8n 2.x changes to review:

- Code node environment variable access is blocked by default.
- `ExecuteCommand` and `LocalFileTrigger` are disabled by default.
- OAuth callback URLs require authentication by default.
- File access is restricted to `~/.n8n-files` by default.
- Python Code nodes use native Python through external task runners; Pyodide-based Python was removed.
- The Start node was removed; use Manual Trigger or Execute Workflow Trigger instead.
- The old active/inactive workflow model changed to publish/unpublish.
- In-memory binary data mode was removed; use filesystem, database, or S3-backed binary data.

Review the official [n8n v2.0 breaking changes](https://docs.n8n.io/2-0-breaking-changes/) before upgrading production.
