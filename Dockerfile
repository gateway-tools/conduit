# Builder
FROM node:16-bullseye-slim as build-test

WORKDIR /build

COPY . .

RUN apt-get update && \
    apt-get install -y \
    --no-install-recommends \ 
    make \
    ca-certificates && \
    make build && \
    make pkg && \
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
