# Optional: a self-contained image. install.sh does not need it; it runs the
# dashboard with the Node already inside the stock dexi-droneblocks image.
FROM node:20-alpine
WORKDIR /app
COPY server.js ./
COPY public ./public
ENV PORT=80
CMD ["node", "server.js"]
