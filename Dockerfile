########################################
# Stage 1 : Build UI + AmneziaWG Go
########################################
FROM docker.io/library/node:jod-alpine AS build

WORKDIR /app

# --- Node setup ---
RUN npm install --global corepack@latest && corepack enable pnpm

# Copy Web UI package files
COPY src/package.json src/pnpm-lock.yaml ./
RUN pnpm install

# Build Web UI
COPY src ./ 
RUN pnpm build

# --- Build amneziawg-go ---
RUN apk add --no-cache go git bash build-base

# Clone amneziawg-go repository
RUN git clone https://github.com/amnezia-vpn/amneziawg-go.git /app/amneziawg-go

# Build the awg binary
RUN cd /app/amneziawg-go && go build -o /app/amneziawg-go/awg ./cmd/awg

########################################
# Stage 2 : Final image
########################################
FROM docker.io/library/node:jod-alpine

WORKDIR /app

# --- Healthcheck ---
HEALTHCHECK --interval=1m --timeout=5s --retries=3 \
  CMD /usr/bin/timeout 5s /bin/sh -c "/usr/bin/wg show | /bin/grep -q interface || exit 1"

# --- Copy UI build ---
COPY --from=build /app/.output /app
COPY --from=build /app/server/database/migrations /app/server/database/migrations
COPY --from=build /app/cli/cli.sh /usr/local/bin/cli
RUN chmod +x /usr/local/bin/cli

# --- Copy AmneziaWG Go binary ---
COPY --from=build /app/amneziawg-go/awg /usr/bin/awg
RUN chmod +x /usr/bin/awg

# --- Linux packages ---
RUN apk add --no-cache \
    dpkg \
    dumb-init \
    iptables \
    ip6tables \
    nftables \
    kmod \
    iptables-legacy \
    wireguard-tools \
    bash

# --- Directories & links ---
RUN mkdir -p /etc/amnezia
RUN ln -s /etc/wireguard /etc/amnezia/amneziawg

# --- Use iptables-legacy ---
RUN update-alternatives --install /usr/sbin/iptables iptables /usr/sbin/iptables-legacy 10 \
    --slave /usr/sbin/iptables-restore iptables-restore /usr/sbin/iptables-legacy-restore \
    --slave /usr/sbin/iptables-save iptables-save /usr/sbin/iptables-legacy-save

RUN update-alternatives --install /usr/sbin/ip6tables ip6tables /usr/sbin/ip6tables-legacy 10 \
    --slave /usr/sbin/ip6tables-restore ip6tables-restore /usr/sbin/ip6tables-legacy-restore \
    --slave /usr/sbin/ip6tables-save ip6tables-save /usr/sbin/ip6tables-legacy-save

# --- Environment variables ---
ENV DEBUG=Server,WireGuard,Database,CMD
ENV PORT=51821
ENV HOST=0.0.0.0
ENV INSECURE=false
ENV INIT_ENABLED=false
ENV DISABLE_IPV6=false

# --- Metadata ---
LABEL org.opencontainers.image.source=https://github.com/wg-easy/wg-easy

# --- Run server ---
CMD ["/usr/bin/dumb-init", "node", "server/index.mjs"]
