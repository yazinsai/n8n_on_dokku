You are working in the `d1ceward-on-dokku/n8n_on_dokku` repository. Implement a pull request that adds proper n8n 2.x support for Dokku deployments.

Important: do not frame the work as "just bumping n8n to v2". The repo currently supports n8n 1.x only. n8n 2.x moves Code node execution to task runners, so the implementation must add support for the external runner architecture.

## Goal

Add production-oriented n8n 2.x support using:

- one Dokku app for the main n8n web/API/webhook/broker container
- one Dokku app for the external task runner container
- a private Dokku network between the two
- matching `n8nio/n8n` and `n8nio/runners` image versions
- preservation of the repo's existing custom Code-node npm packages

The final PR should be suitable for the upstream repository owner to review and merge.

## Current repo shape

The repo is a thin Dokku wrapper around the official n8n image.

Current important files:

- `Dockerfile`
  - extends `n8nio/n8n`
  - pins `ARG N8N_VERSION`
  - currently installs Code-node packages in the main image
  - currently sets `NODE_FUNCTION_ALLOW_EXTERNAL`
  - currently sets `NODE_FUNCTION_ALLOW_BUILTIN`
- `entrypoint.sh`
  - maps Dokku `PORT` to `N8N_PORT`
  - parses Dokku Postgres `DATABASE_URL`
  - exports `DB_TYPE=postgresdb` and `DB_POSTGRESDB_*`
  - runs `exec n8n`
- `README.md`
  - documents a single-app Dokku deployment
  - currently says v2 is unsupported
- `update`
  - currently filters to latest `1.x`
  - blocks `2.x`
  - updates only `Dockerfile` and README badge

## Required architecture

Implement the v2 deployment as two Dokku apps from the same repo:

```txt
n8n          -> main n8n app: web UI, API, webhooks, task broker
n8n-runners  -> external task runner app
```

Image mapping:

```txt
Dockerfile          -> FROM n8nio/n8n:${N8N_VERSION}
Dockerfile.runners  -> FROM n8nio/runners:${N8N_VERSION}
```

The runner app must connect to the main app's task broker:

```txt
http://n8n.web:5679
```

The runner app must not be publicly proxied.

## Implementation tasks

### 1. Update `Dockerfile`

Make the main Dockerfile responsible only for running n8n itself.

Expected shape:

```Dockerfile
ARG N8N_VERSION="2.x.x"

FROM n8nio/n8n:${N8N_VERSION}

USER root

COPY ./entrypoint.sh /custom-entrypoint.sh

RUN chown node:node /custom-entrypoint.sh && \
    chmod +x /custom-entrypoint.sh

ENV SHELL=/bin/sh

USER node

ENTRYPOINT ["/custom-entrypoint.sh"]
```

Remove from the main image:

- npm installs for Code-node modules
- `NODE_FUNCTION_ALLOW_EXTERNAL`
- `NODE_FUNCTION_ALLOW_BUILTIN`

Those belong in the runner image/config for external runner mode.

### 2. Add `Dockerfile.runners`

Add a new Dockerfile for the external task runner app.

Expected shape:

```Dockerfile
ARG N8N_VERSION="2.x.x"

FROM n8nio/runners:${N8N_VERSION}

USER root

RUN cd /opt/runners/task-runner-javascript && \
    pnpm add node-fetch @paralleldrive/cuid2 franc @distube/ytdl-core

COPY ./n8n-task-runners.json /etc/n8n-task-runners.json

USER runner
```

Notes:

- Use the same `N8N_VERSION` value as the main `Dockerfile`.
- Preserve the existing custom package set from the v1 image.
- The old Dockerfile used `@distube/ytdl-core@latest`. Prefer the package manager's current latest resolution unless you decide to pin it for reproducibility. If you pin it, explain why in the PR.

### 3. Add `n8n-task-runners.json`

Add a runner launcher config copied into the runner image at exactly:

```txt
/etc/n8n-task-runners.json
```

Do not use an incomplete minimal config unless you verify it works. Preserve the default JavaScript and Python runner command/args/health-check structure from the official `n8nio/runners` image, and customize the JavaScript runner `env-overrides`.

The JavaScript runner must preserve this existing behavior:

```txt
NODE_FUNCTION_ALLOW_BUILTIN="*"
NODE_FUNCTION_ALLOW_EXTERNAL="node-fetch,@paralleldrive/cuid2,franc,@distube/ytdl-core"
```

The config should include a JavaScript runner and Python runner unless upstream docs or current image behavior prove a different shape is required.

### 4. Update `entrypoint.sh`

Keep the existing Dokku behavior:

- if `PORT` exists, export `N8N_PORT="$PORT"`
- parse `DATABASE_URL`
- export:
  - `DB_TYPE=postgresdb`
  - `DB_POSTGRESDB_HOST`
  - `DB_POSTGRESDB_PORT`
  - `DB_POSTGRESDB_DATABASE`
  - `DB_POSTGRESDB_USER`
  - `DB_POSTGRESDB_PASSWORD`
- support `/opt/custom-certificates`
- run `exec n8n`

Also fix the current password leak:

- remove or replace the line that logs the full Postgres URL with credentials

Prefer a clear error if `DATABASE_URL` is missing, because this deployment expects Dokku Postgres to be linked to the main app.

### 5. Rewrite `README.md`

The README must become a v2-compatible Dokku deployment guide.

Include:

#### Overview

Explain that n8n 2.x requires task runners for Code node execution and this repo deploys:

- a main n8n Dokku app
- a private external runner Dokku app

#### Prerequisites

Include:

- Dokku
- dokku-postgres plugin
- optional dokku-letsencrypt plugin
- Dokku network support

#### App creation

Document:

```bash
dokku apps:create n8n
dokku apps:create n8n-runners
```

#### Dockerfile paths

Document:

```bash
dokku builder-dockerfile:set n8n dockerfile-path Dockerfile
dokku builder-dockerfile:set n8n-runners dockerfile-path Dockerfile.runners
```

#### Postgres

Postgres should be linked only to the main app:

```bash
dokku postgres:create n8n
dokku postgres:link n8n n8n
```

#### Private network

Document:

```bash
dokku network:create n8n-internal
dokku network:set n8n attach-post-create n8n-internal
dokku network:set n8n-runners attach-post-create n8n-internal
```

#### Main app config

Document setting:

```bash
dokku config:set n8n \
  N8N_ENCRYPTION_KEY="<generated-key>" \
  WEBHOOK_URL="https://n8n.example.com" \
  N8N_RUNNERS_ENABLED=true \
  N8N_RUNNERS_MODE=external \
  N8N_RUNNERS_BROKER_LISTEN_ADDRESS=0.0.0.0 \
  N8N_RUNNERS_AUTH_TOKEN="<shared-runner-token>"
```

Use a secure shell-friendly example to generate the encryption key and runner token.

#### Runner app config

Document:

```bash
dokku config:set n8n-runners \
  N8N_RUNNERS_TASK_BROKER_URI=http://n8n.web:5679 \
  N8N_RUNNERS_AUTH_TOKEN="<same-shared-runner-token>"
```

#### Runner proxy

Document:

```bash
dokku proxy:disable n8n-runners
```

Only the main app should be publicly exposed.

#### Storage

Keep persistent storage for the main app:

```bash
dokku storage:ensure-directory n8n --chown false
chown 1000:1000 /var/lib/dokku/data/storage/n8n
dokku storage:mount n8n /var/lib/dokku/data/storage/n8n:/home/node/.n8n
```

Consider whether to document `~/.n8n-files` or `N8N_RESTRICT_FILE_ACCESS_TO` for v2 file-node behavior. If you add this, keep it simple and explain why.

#### Ports and domains

Document public ports only on `n8n`:

```bash
dokku domains:set n8n n8n.example.com
dokku ports:set n8n http:80:5678
dokku ports:add n8n https:443:5678
```

#### Deploy

Document both `git:sync` and manual git remote options.

For `git:sync`:

```bash
dokku git:sync --build n8n https://github.com/d1ceward-on-dokku/n8n_on_dokku.git
dokku git:sync --build n8n-runners https://github.com/d1ceward-on-dokku/n8n_on_dokku.git
```

For manual pushes:

```bash
git remote add dokku-n8n dokku@example.com:n8n
git remote add dokku-n8n-runners dokku@example.com:n8n-runners

git push dokku-n8n master
git push dokku-n8n-runners master
```

#### v1 -> v2 migration notes

Add a migration section for existing users:

1. upgrade to latest v1 first
2. run the n8n v2 Migration Report in the n8n UI
3. fix critical workflow and instance issues
4. back up Postgres and `/home/node/.n8n`
5. deploy the v2 main app and runner app

Call out common v2 changes:

- Code node environment variable access is blocked by default
- `ExecuteCommand` and `LocalFileTrigger` are disabled by default
- OAuth callback auth default changes
- file access is restricted by default
- Python Code node behavior changes
- Start node removed
- active/inactive workflow model changes to publish/unpublish
- in-memory binary data mode removed

### 6. Update `update`

Rewrite the update script so it supports v2.

Requirements:

- select latest stable `2.x` release from n8n GitHub releases
- update `ARG N8N_VERSION` in both:
  - `Dockerfile`
  - `Dockerfile.runners`
- update the README n8n badge/version reference
- keep the two image versions synchronized
- remove the current block that prevents `2.x`

Keep the script style consistent with the existing script unless there is a clear reason to improve it.

### 7. Add Docker build CI

Add `.github/workflows/docker-build.yml`.

Minimum workflow:

```yaml
name: Docker build

on:
  pull_request:
  push:
    branches:
      - master

jobs:
  docker-build:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Build n8n image
        run: docker build -t n8n-on-dokku .

      - name: Build runner image
        run: docker build -f Dockerfile.runners -t n8n-on-dokku-runners .
```

If build time is too high, keep the workflow but mention it in the PR.

## Validation

At minimum run:

```bash
docker build -t n8n-on-dokku .
docker build -f Dockerfile.runners -t n8n-on-dokku-runners .
```

Also validate text/script consistency:

- both Dockerfiles use the same `N8N_VERSION`
- README badge matches that version
- `update` modifies both Dockerfiles
- runner config path is exactly `/etc/n8n-task-runners.json`
- runner allowlist includes the existing custom packages

If you have access to a Dokku host, smoke test:

- main app boots
- runner app boots
- runner app connects to broker on `n8n.web:5679`
- runner app is not publicly proxied
- UI loads
- Postgres persistence works
- webhook URL works
- JavaScript Code node can import:
  - `node-fetch`
  - `@paralleldrive/cuid2`
  - `franc`
  - `@distube/ytdl-core`

## PR expectations

Create a clean PR with a title like:

```txt
Add n8n 2.x support with external task runners
```

PR body should include:

- summary of architecture
- files changed
- why external runners are required
- migration notes
- verification commands and results
- any limitations, especially if Dokku runtime smoke testing was not possible

Do not include unrelated refactors.
Do not remove Dokku Postgres support.
Do not switch the repo to docker-compose.
Do not make the runner publicly exposed.
