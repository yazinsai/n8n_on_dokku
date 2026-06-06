#!/bin/sh

# Check if PORT variable is set, otherwise use the default
if [ -z "${PORT+x}" ]; then
  echo "PORT variable not defined, leaving N8N to default port."
else
  export N8N_PORT="$PORT"
  echo "N8N will start on '$PORT'"
fi

if [ -z "${DATABASE_URL:-}" ]; then
  echo "DATABASE_URL is required. Link a Dokku Postgres service to the n8n app." >&2
  exit 1
fi

if ! database_exports="$(node <<'EOF'
const databaseUrl = process.env.DATABASE_URL;

function shellQuote(value) {
  return `'${String(value).replace(/'/g, `'\\''`)}'`;
}

try {
  const url = new URL(databaseUrl);
  const scheme = url.protocol.replace(/:$/, '');

  if (scheme !== 'postgres' && scheme !== 'postgresql') {
    throw new Error(`Unsupported database scheme: ${scheme}`);
  }

  const database = decodeURIComponent(url.pathname.replace(/^\//, ''));

  if (!url.hostname || !database || !url.username) {
    throw new Error('DATABASE_URL must include host, database, and user');
  }

  const values = {
    DB_TYPE: 'postgresdb',
    DB_POSTGRESDB_HOST: url.hostname,
    DB_POSTGRESDB_PORT: url.port || '5432',
    DB_POSTGRESDB_DATABASE: database,
    DB_POSTGRESDB_USER: decodeURIComponent(url.username),
    DB_POSTGRESDB_PASSWORD: decodeURIComponent(url.password),
  };

  for (const [key, value] of Object.entries(values)) {
    console.log(`export ${key}=${shellQuote(value)}`);
  }
} catch (error) {
  console.error(`Invalid DATABASE_URL: ${error.message}`);
  process.exit(1);
}
EOF
)"; then
  exit 1
fi

eval "$database_exports"
echo "Configured Postgres database '$DB_POSTGRESDB_DATABASE' on '$DB_POSTGRESDB_HOST:$DB_POSTGRESDB_PORT'."

if [ -d /opt/custom-certificates ]; then
  echo "Trusting custom certificates from /opt/custom-certificates."
  export NODE_OPTIONS="--use-openssl-ca $NODE_OPTIONS"
  export SSL_CERT_DIR=/opt/custom-certificates
  c_rehash /opt/custom-certificates
fi

exec n8n
