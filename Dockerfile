FROM rust:alpine AS builder

WORKDIR /build

COPY ./crates/ ./crates/
COPY Cargo.toml Cargo.lock ./

RUN apk add build-base
RUN cargo build --release

FROM alpine:3.19

WORKDIR /

# iproute2 : ip command (BusyBox's ip command does not work)
RUN apk add --no-cache \
    bash \
    curl \
    socat \
    dnsmasq-dnssec \
    dhclient \
    inotify-tools \
    iproute2 \
    iptables

COPY ./src/ /pgw/
COPY --from=builder /build/target/release/pgw-logger /pgw/pgw-logger

RUN chmod +x /pgw/pgw-logger
RUN chmod +x /pgw/*.sh
RUN chmod +x /pgw/client/*.sh
RUN chmod +x /pgw/gateway/*.sh

ENTRYPOINT ["/pgw/entry.sh"]
