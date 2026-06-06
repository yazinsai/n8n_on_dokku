ARG N8N_VERSION="2.25.5"

FROM n8nio/n8n:${N8N_VERSION}

USER root

COPY ./entrypoint.sh /custom-entrypoint.sh

RUN chown node:node /custom-entrypoint.sh && \
    chmod +x /custom-entrypoint.sh

ENV SHELL=/bin/sh

USER node

ENTRYPOINT ["/custom-entrypoint.sh"]
