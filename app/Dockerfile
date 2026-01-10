# syntax=docker/dockerfile:1
FROM golang:1.25-alpine AS build
ARG LISTMONK_VERSION=v6.0.0
RUN apk add --no-cache git ca-certificates build-base
WORKDIR /src
RUN git clone --depth 1 --branch ${LISTMONK_VERSION} https://github.com/knadh/listmonk.git .
RUN CGO_ENABLED=0 go build -o /out/listmonk ./cmd/listmonk

FROM alpine:3.21.3
RUN addgroup -S app && adduser -S -G app -u 10001 app     && apk add --no-cache ca-certificates busybox
WORKDIR /app
COPY --from=build /out/listmonk /app/listmonk
COPY docker/entrypoint.sh /app/entrypoint.sh
RUN chmod +x /app/entrypoint.sh && chown -R app:app /app
USER 10001
EXPOSE 9000
ENTRYPOINT ["/app/entrypoint.sh"]
