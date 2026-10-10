FROM node:24-alpine
WORKDIR /app
COPY --chown=node:node package*.json ./
RUN npm ci --omit=dev
COPY --chown=node:node src ./src
COPY --chown=node:node scripts ./scripts
COPY --chown=node:node migrations ./migrations
ENV NODE_ENV=production HOST=0.0.0.0 PORT=8787
USER node
EXPOSE 8787
CMD ["node", "src/server.js"]
