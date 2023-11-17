# Builder

ARG NODEJS_VERSION=18
FROM node:${NODEJS_VERSION}-bullseye-slim as build-test

ARG NODEJS_VERSION

WORKDIR /build

COPY src .

RUN apt-get update && \
    apt-get install -y \
    --no-install-recommends \ 
    make \
    python3 \
    build-essential \
    ca-certificates && \
    npm install && \
    set -x && \
    ./node_modules/.bin/pkg -t node${NODEJS_VERSION}-linuxstatic-x64 index.js && \
    useradd -u 10005 proxyuser && \
    tail -n 1 /etc/passwd > /etc/passwd.scratch

FROM scratch as runtime

WORKDIR /app

COPY --from=build-test /build/index ./resolver
COPY --from=build-test /etc/ssl /etc/ssl
COPY --from=build-test /etc/passwd.scratch /etc/passwd

ENV PATH="${PATH}:/app"

USER 10005

CMD ["resolver"]
