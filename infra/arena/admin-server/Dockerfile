FROM node:20-alpine
RUN apk add --no-cache docker-cli docker-cli-compose
WORKDIR /app
COPY package.json .
RUN npm install --omit=dev
COPY server.js .
EXPOSE 8082
CMD ["node", "server.js"]
