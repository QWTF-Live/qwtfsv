# The FortressOne server node: five shards, the updater, the crash reporter and
# the certificate watcher in one container, supervised by s6.
#
# What stays outside: certbot (upstream's image, so ACME fixes arrive by pull
# rather than waiting on a rebuild here) and qwfwd (not built from this repo).
FROM ubuntu:24.04
WORKDIR /qwtfsv
ARG FTE_CONFIG=qwtflive
ARG S6_OVERLAY_VERSION=3.2.0.2

RUN apt-get update \
 && apt-get install -y \
    curl \
    gcc \
    inotify-tools \
    libgnutls28-dev \
    libpng-dev \
    make \
    mesa-common-dev \
    python3 \
    python3-venv \
    subversion \
    tmux \
    util-linux \
    xz-utils \
    zlib1g-dev \
 && rm -rf /var/lib/apt/lists/*

# 24.04 marks the system interpreter externally-managed, so awscli gets its own
# venv. sync.sh calls /usr/local/bin/aws by absolute path; keep that true.
RUN python3 -m venv /opt/awscli \
 && /opt/awscli/bin/pip install --no-cache-dir --upgrade pip awscli \
 && ln -s /opt/awscli/bin/aws /usr/local/bin/aws

ADD https://github.com/just-containers/s6-overlay/releases/download/v${S6_OVERLAY_VERSION}/s6-overlay-noarch.tar.xz /tmp/s6-noarch.tar.xz
ADD https://github.com/just-containers/s6-overlay/releases/download/v${S6_OVERLAY_VERSION}/s6-overlay-x86_64.tar.xz /tmp/s6-x86_64.tar.xz
RUN tar -C / -Jxpf /tmp/s6-noarch.tar.xz \
 && tar -C / -Jxpf /tmp/s6-x86_64.tar.xz \
 && rm /tmp/s6-noarch.tar.xz /tmp/s6-x86_64.tar.xz

COPY . /qwtfsv/
COPY --from=qwtflive/updater:latest /updater /updater
# Staged into the context by build_and_push.sh: crashwatch is a sibling
# checkout, and a COPY cannot reach outside the build context.
COPY vendor/qwtf_crashwatch.py /opt/crashwatch/qwtf_crashwatch.py

RUN cd /qwtfsv/fortress/dats/ \
 && curl \
    --location \
    --remote-name-all \
    https://qwtflive-dats.s3.amazonaws.com/staging/{qwprogs,csprogs,menu}.dat \
 && cd /qwtfsv/

RUN ln -sf /qwtfsv/bin/fo-shard     /usr/local/bin/fo-shard \
 && ln -sf /qwtfsv/bin/fo-console   /usr/local/bin/fo-console \
 && ln -sf /qwtfsv/bin/fo-players   /usr/local/bin/fo-players \
 && ln -sf /qwtfsv/bin/fo-certwatch /usr/local/bin/fo-certwatch \
 && ln -sf /usr/local/bin/fo-console /usr/local/bin/console

# One s6 service per row of shards.conf, so adding a shard is a one-line edit
# there rather than a new directory here.
COPY s6/ /etc/s6-overlay/s6-rc.d/
RUN set -eu; \
    awk '$1 !~ /^#/ && NF {print $1}' /qwtfsv/shards.conf | while read -r name; do \
      dir="/etc/s6-overlay/s6-rc.d/$name"; \
      mkdir -p "$dir/dependencies.d"; \
      echo longrun > "$dir/type"; \
      touch "$dir/dependencies.d/init"; \
      printf '#!/command/with-contenv bash\nexec fo-shard %s\n' "$name" > "$dir/run"; \
      chmod +x "$dir/run"; \
      touch "/etc/s6-overlay/s6-rc.d/user/contents.d/$name"; \
    done

# Host networking, so the ports are documentation rather than publication.
EXPOSE 27500/udp 27501/udp 27504/udp 27505/udp 27510/udp

# KEEP_ENV: the shards read TF_* straight from the container environment.
# STAGE2_FAILS=2: if fo-init cannot lay out /srv there is no point coming
# up half-configured - fail the container so `up -d` reports it.
ENV S6_KEEP_ENV=1 \
    S6_CMD_WAIT_FOR_SERVICES_MAXTIME=0 \
    S6_BEHAVIOUR_IF_STAGE2_FAILS=2

ENTRYPOINT ["/init"]
