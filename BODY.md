@d1ceward I’m going to work on adding proper n8n 2.x support for this repo.

Based on the v2 breaking changes and your note in #5, simply bumping `N8N_VERSION` in the existing `Dockerfile` is not enough. n8n 2.x moves Code node execution to task runners, and the production Docker setup needs a separate `n8nio/runners` container connected to the main n8n instance.

## Proposed approach

Add v2 support using two Dokku apps from this same repo:

- `n8n` — main web/API/webhook/broker app
- `n8n-runners` — external task runner app

The main app will continue to use `n8nio/n8n:<version>`, while the runner app will use `n8nio/runners:<same-version>`. The two apps will communicate over a private Dokku network, with the runner connecting to the n8n task broker on port `5679`.

## Planned repo changes

### 1. Update the main `Dockerfile`

The main image should only run n8n itself.

Planned changes:

- update `ARG N8N_VERSION` to a 2.x version
- keep the existing Dokku entrypoint behavior
- remove Code-node npm dependency installation from the main image
- remove `NODE_FUNCTION_ALLOW_*` from the main image, since external runners need those configured in the runner environment/config instead

### 2. Add `Dockerfile.runners`

Add a new runner Dockerfile based on:

```Dockerfile
FROM n8nio/runners:${N8N_VERSION}
```

This image will install the existing custom Code-node packages currently installed in the main image:

- `node-fetch`
- `@paralleldrive/cuid2`
- `franc`
- `@distube/ytdl-core`

The runner image version will be kept in sync with the main n8n image version.

### 3. Add `n8n-task-runners.json`

Add a runner config file copied to:

```txt
/etc/n8n-task-runners.json
```

This config will preserve the default JavaScript/Python runner command, args, health-check ports, and allowed env structure, while changing the JavaScript runner `env-overrides` to preserve the repo’s current Code-node behavior:

```json
{
  "NODE_FUNCTION_ALLOW_BUILTIN": "*",
  "NODE_FUNCTION_ALLOW_EXTERNAL": "node-fetch,@paralleldrive/cuid2,franc,@distube/ytdl-core"
}
```

### 4. Update `entrypoint.sh`

Keep the existing Dokku glue:

- map Dokku `PORT` to `N8N_PORT`
- parse `DATABASE_URL`
- export `DB_POSTGRESDB_*`
- support `/opt/custom-certificates`

Also clean up the current database logging so the Postgres password is not printed to logs.

### 5. Rewrite the README deployment guide

Update the README from a single-app Dokku deployment to a v2-compatible two-app deployment.

The new flow will document:

```bash
dokku apps:create n8n
dokku apps:create n8n-runners
```

Configure Dockerfile paths:

```bash
dokku builder-dockerfile:set n8n dockerfile-path Dockerfile
dokku builder-dockerfile:set n8n-runners dockerfile-path Dockerfile.runners
```

Create a private network:

```bash
dokku network:create n8n-internal
dokku network:set n8n attach-post-create n8n-internal
dokku network:set n8n-runners attach-post-create n8n-internal
```

Configure the main app:

```bash
dokku config:set n8n \
  N8N_RUNNERS_ENABLED=true \
  N8N_RUNNERS_MODE=external \
  N8N_RUNNERS_BROKER_LISTEN_ADDRESS=0.0.0.0 \
  N8N_RUNNERS_AUTH_TOKEN="<shared-secret>"
```

Configure the runner app:

```bash
dokku config:set n8n-runners \
  N8N_RUNNERS_TASK_BROKER_URI=http://n8n.web:5679 \
  N8N_RUNNERS_AUTH_TOKEN="<same-shared-secret>"
```

Disable public proxying for the runner app:

```bash
dokku proxy:disable n8n-runners
```

Keep public ports only on the main app:

```bash
dokku ports:set n8n http:80:5678
dokku ports:add n8n https:443:5678
```

### 6. Document v1 -> v2 migration considerations

Add a migration section that tells existing users to:

1. upgrade to the latest v1 first
2. run the n8n v2 Migration Report from the n8n UI
3. fix critical workflow and instance issues
4. back up Postgres and `/home/node/.n8n`
5. deploy the v2 main app and runner app

The docs should also call out common v2 breaking changes:

- Code node environment variable access blocked by default
- `ExecuteCommand` and `LocalFileTrigger` disabled by default
- OAuth callback authentication default change
- file access restricted by default
- Python Code node behavior changes
- Start node removal
- workflow publish/unpublish model

### 7. Update the `update` script

The current update script intentionally filters to `1.x` and blocks `2.x`.

Planned changes:

- select latest stable `2.x`
- update both `Dockerfile` and `Dockerfile.runners`
- update the README badge
- keep main and runner image versions synchronized

### 8. Add Docker build validation

Add a small GitHub Actions workflow to build both images:

```bash
docker build -t n8n-on-dokku .
docker build -f Dockerfile.runners -t n8n-on-dokku-runners .
```

This will not fully validate Dokku networking, but it will catch broken Dockerfiles and runner image issues.

## Validation plan

Before opening the PR, I’ll verify:

- main Docker image builds
- runner Docker image builds
- `N8N_VERSION` is synchronized across both Dockerfiles
- README instructions are internally consistent
- runner config is copied to the exact expected path
- existing custom Code-node package allowlist is preserved in the runner config

If possible, I’ll also smoke test on Dokku:

- main app boots
- runner app connects to the broker
- runner app is not publicly proxied
- UI loads
- Postgres persistence works
- webhook URL works
- JavaScript Code node can import the custom packages

## Expected result

The PR should make this repo support n8n 2.x using the recommended external task runner architecture while keeping the deployment model understandable for Dokku users.
