# ==========================
# Stage 1 : build Web UI + awg
# ==========================
FROM docker.io/library/node:jod-alpine AS build
WORKDIR /app

# Update corepack et installer pnpm
RUN npm install --global corepack@latest
RUN corepack enable pnpm

# Copier Web UI et installer dépendances
COPY src/package.json src/pnpm-lock.yaml ./
RUN pnpm install
COPY src ./ 
RUN pnpm build

# Installer outils build
RUN apk add --no-cache linux-headers build-base git go bash

# Cloner et compiler amneziawg-go
RUN git clone https://github.com/amnezia-vpn/amneziawg-go.git /app/amneziawg-go \
    && cd /app/amneziawg-go \
    && go build -o /usr/bin/awg ./cmd/awg \
    && chmod +x /usr/bin/awg

# ==========================
# Stage 2 : runtime image
# ==========================
FROM docker.io/library/node:jod-alpine
WORKDIR /app

# Installer packages runtime
RUN apk add --no-cache \
    dpkg \
    dumb-init \
    bash \
    iptables \
    ip6tables \
    nftables \
    kmod \
    iptables-legacy \
    wireguard-tools

# Healthcheck minimal
HEALTHCHECK --interval=1m --timeout=5s --retries=3 \
    CMD /usr/bin/timeout 5s /bin/sh -c "/usr/bin/wg show | /bin/grep -q interface || exit 1"

# Copier Web UI et migrations
COPY --from=build /app/.output /app
COPY --from=build /app/server/database/migrations /app/server/database/migrations

# Installer libsql
RUN cd /app/server && npm install --no-save libsql && npm cache clean --force

# Copier CLI
COPY --from=build /app/cli/cli.sh /usr/local/bin/cli
RUN chmod +x /usr/local/bin/cli

# Copier le binaire awg
COPY --from=build /usr/bin/awg /usr/bin/awg
RUN chmod +x /usr/bin/awg

# Configuration /etc/amnezia
RUN mkdir -p /etc/amnezia \
    && ln -s /etc/wireguard /etc/amnezia/amneziawg

# Configurer iptables-legacy
RUN update-alternatives --install /usr/sbin/iptables iptables /usr/sbin/iptables-legacy 10 \
    --slave /usr/sbin/iptables-restore iptables-restore /usr/sbin/iptables-legacy-restore \
    --slave /usr/sbin/iptables-save iptables-save /usr/sbin/iptables-legacy-save
RUN update-alternatives --install /usr/sbin/ip6tables ip6tables /usr/sbin/ip6tables-legacy 10 \
    --slave /usr/sbin/ip6tables-restore ip6tables-restore /usr/sbin/ip6tables-legacy-restore \
    --slave /usr/sbin/ip6tables-save ip6tables-save /usr/sbin/ip6tables-legacy-save

# Variables d'environnement
ENV DEBUG=Server,WireGuard,Database,CMD
ENV PORT=51821
ENV HOST=0.0.0.0
ENV INSECURE=false
ENV INIT_ENABLED=false
ENV DISABLE_IPV6=false

# CMD debug-friendly pour que le conteneur reste vivant
CMD ["tail", "-f", "/dev/null"]
