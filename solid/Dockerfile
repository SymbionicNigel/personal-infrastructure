FROM node:16

WORKDIR /usr/src/solid

RUN curl -f https://get.pnpm.io/v7.17.js | node - add --global pnpm

# pnpm fetch does require only lockfile
COPY pnpm-lock.yaml ./

ADD . ./

RUN pnpm install -r --offline --prod

RUN pnpm run build

EXPOSE 3000
CMD [ "pnpm", 'run', 'start']

