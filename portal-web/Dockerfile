FROM node:24-alpine
WORKDIR /app
COPY --chown=node:node index.html dev_server.mjs ./
COPY --chown=node:node src ./src
ENV NODE_ENV=production PORT=4173
USER node
EXPOSE 4173
CMD ["node", "dev_server.mjs"]
