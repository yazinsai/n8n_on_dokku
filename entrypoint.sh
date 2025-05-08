#!/bin/sh

# Check if PORT variable is set, otherwise use the default
if [ -z "${PORT+x}" ]; then
  echo "PORT variable not defined, leaving N8N to default port."
else
  export N8N_PORT="$PORT"
  echo "N8N will start on '$PORT'"
fi

# Function to parse a URL into its components
parse_url() {
  eval "$(echo "$1" | sed -E \
    -e "s#^(([^:]+)://)?(([^:@]+)(:([^@]+))?@)?([^/?]+)(/(.*))?#\
${PREFIX:-URL_}SCHEME='\2' \
${PREFIX:-URL_}USER='\4' \
${PREFIX:-URL_}PASSWORD='\6' \
${PREFIX:-URL_}HOSTPORT='\7' \
${PREFIX:-URL_}DATABASE='\9'#")"
}

# Parse the DATABASE_URL and extract components
PREFIX="N8N_DB_" parse_url "$DATABASE_URL"
echo "$N8N_DB_SCHEME://$N8N_DB_USER:$N8N_DB_PASSWORD@$N8N_DB_HOSTPORT/$N8N_DB_DATABASE"

# Separate host and port
N8N_DB_HOST="$(echo "$N8N_DB_HOSTPORT" | sed -E 's,:.*,,')"
N8N_DB_PORT="$(echo "$N8N_DB_HOSTPORT" | sed -E 's,.*:([0-9]+).*,\1,')"

# Export database environment variables
export DB_TYPE="postgresdb"
export DB_POSTGRESDB_HOST="$N8N_DB_HOST"
export DB_POSTGRESDB_PORT="$N8N_DB_PORT"
export DB_POSTGRESDB_DATABASE="$N8N_DB_DATABASE"
export DB_POSTGRESDB_USER="$N8N_DB_USER"
export DB_POSTGRESDB_PASSWORD="$N8N_DB_PASSWORD"

tini -- /docker-entrypoint.sh
