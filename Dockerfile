# =============================================================================
# Absolute Satisfactory Server
# =============================================================================
# Built from absolute-server-template. Everything game-specific is in
# manifest.env; this file differs from the next game's only in the base image
# and the packages the game itself needs.
# =============================================================================

# Pinned by digest, not by tag: a tag can change under a rebuild with no commit.
# debian-bookworm-slim is the approved entry in absolute-standard's base image
# library. It is not a hardened distribution, and the reason is recorded in
# .absolute/policy.yml: SteamCMD is a 32-bit binary needing glibc multiarch,
# which nothing hardened in the library has yet been proven to provide.
FROM debian:bookworm-slim@sha256:3783cc01769c7b2b1b83a5c5ad96c815348e28ed7da68e2e3687004faa906251 AS base

ENV DEBIAN_FRONTEND=noninteractive

RUN dpkg --add-architecture i386 \
    && apt-get update \
    && apt-get install -y --no-install-recommends \
        ca-certificates curl tini supervisor cron \
        lib32gcc-s1 lib32stdc++6 libc6-i386 \
        python3-minimal jq unzip rsync procps \
    && rm -rf /var/lib/apt/lists/*

# -----------------------------------------------------------------------------
FROM base AS steamcmd

RUN mkdir -p /opt/steamcmd \
    && curl -sqL "https://steamcdn-a.akamaihd.net/client/installer/steamcmd_linux.tar.gz" \
       | tar zxf - -C /opt/steamcmd \
    && chmod +x /opt/steamcmd/steamcmd.sh \
    && /opt/steamcmd/steamcmd.sh +quit || true

# -----------------------------------------------------------------------------
FROM base AS runtime

ARG GAME_ID=satisfactory
ARG GAME_UID=1000

COPY --from=steamcmd /opt/steamcmd /opt/steamcmd

RUN groupadd -g ${GAME_UID} ${GAME_ID} \
    && useradd -u ${GAME_UID} -g ${GAME_ID} -m -s /bin/bash ${GAME_ID}

# The server loads steamclient.so from its own $HOME. SteamCMD leaves a copy
# under /root, which an unprivileged user cannot even traverse - that failure
# cost the Rust image months of a server that never started
# (abspwgm/absolute-rust-server#14). Put it where the server user can read it,
# and give the process the right HOME in supervisord.conf.
RUN mkdir -p /home/${GAME_ID}/.steam/sdk64 /home/${GAME_ID}/.steam/sdk32 \
    && cp /opt/steamcmd/linux64/steamclient.so /home/${GAME_ID}/.steam/sdk64/steamclient.so \
    && cp /opt/steamcmd/linux32/steamclient.so /home/${GAME_ID}/.steam/sdk32/steamclient.so \
    && chown -R ${GAME_ID}:${GAME_ID} /home/${GAME_ID} \
    && chmod 0755 /home/${GAME_ID}

RUN mkdir -p /opt/${GAME_ID}/server /opt/${GAME_ID}/scripts \
             /config /var/log/${GAME_ID} /var/run/${GAME_ID} \
    && chown -R ${GAME_ID}:${GAME_ID} /opt/${GAME_ID} /config \
             /var/log/${GAME_ID} /var/run/${GAME_ID}

COPY manifest.env /opt/manifest.env
COPY scripts/ /opt/${GAME_ID}/scripts/
COPY config/supervisord.conf /etc/supervisor/conf.d/game.conf

RUN find /opt/${GAME_ID}/scripts -type f -exec sed -i 's/\r$//' {} \; \
    && chmod +x /opt/${GAME_ID}/scripts/*

ENV GAME_ID=${GAME_ID} \
    UPDATE_ON_START=true \
    BACKUPS_ENABLED=true \
    BACKUPS_MAX_COUNT=10 \
    SERVER_PORT=7777 \
    TZ=Etc/UTC

EXPOSE 7777/udp 7777/tcp 8888/tcp

HEALTHCHECK --interval=30s --timeout=10s --start-period=600s --retries=3 \
    CMD /opt/satisfactory/scripts/healthcheck || exit 1

ENTRYPOINT ["/usr/bin/tini", "--"]
CMD ["/opt/satisfactory/scripts/bootstrap"]
