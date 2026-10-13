FROM node:22-bookworm-slim

WORKDIR /app
COPY package*.json ./
RUN npm install --omit=dev --no-audit --no-fund

COPY server.js ./
EXPOSE 4000/tcp
EXPOSE 20000-20100/udp
EXPOSE 20000-20100/tcp

CMD ["node", "server.js"]
