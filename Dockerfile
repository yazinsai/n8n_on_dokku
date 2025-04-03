ARG N8N_VERSION="1.85.4"

FROM n8nio/n8n:${N8N_VERSION}

USER root

# Install custom modules
RUN npm install -g @paralleldrive/cuid2 franc

COPY ./entrypoint.sh /docker-entrypoint.sh

RUN chown node:node /docker-entrypoint.sh && \
    chmod +x /docker-entrypoint.sh

# Allow all modules
ENV NODE_FUNCTION_ALLOW_EXTERNAL="*"
ENV NODE_FUNCTION_ALLOW_BUILTIN="*"
ENV N8N_CUSTOM_EXTENSIONS="@paralleldrive/cuid2 franc"

USER node

EXPOSE 5000/tcp

ENTRYPOINT ["/docker-entrypoint.sh"]
