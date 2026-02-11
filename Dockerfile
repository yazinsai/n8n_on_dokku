ARG N8N_VERSION="1.123.20"

FROM n8nio/n8n:${N8N_VERSION}

USER root

# Install custom modules globally
RUN npm install -g @paralleldrive/cuid2 franc @distube/ytdl-core@latest

COPY ./entrypoint.sh /custom-entrypoint.sh

RUN chown node:node /custom-entrypoint.sh && \
    chmod +x /custom-entrypoint.sh

# Allow specific external modules
# Make sure to prepend 'node-fetch' to the list
ENV NODE_FUNCTION_ALLOW_EXTERNAL="node-fetch,@paralleldrive/cuid2,franc,@distube/ytdl-core"
ENV NODE_FUNCTION_ALLOW_BUILTIN="*"

ENV SHELL /bin/sh
USER node

ENTRYPOINT ["/custom-entrypoint.sh"]
