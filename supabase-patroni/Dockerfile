# =============================================================================
# Supabase PostgreSQL with Patroni and etcd Support
# =============================================================================
#
# This Dockerfile creates a PostgreSQL image with:
# - PostgreSQL 16 with Supabase extensions
# - Patroni for high availability
# - Support for etcd, consul, zookeeper, and kubernetes DCS backends
#
# Based on Zalando Spilo's architecture
#
# Build:
#   docker build -t supabase-patroni:latest -f Dockerfile .
#
# Run (with external etcd):
#   docker run -d \
#     -e PATRONI_NAME=node1 \
#     -e PATRONI_SCOPE=supabase-ha \
#     -e PATRONI_ETCD_HOSTS=etcd1:2379,etcd2:2379,etcd3:2379 \
#     -e POSTGRES_PASSWORD=secure_password \
#     -e REPLICATION_PASSWORD=repl_password \
#     -p 5432:5432 -p 8008:8008 \
#     supabase-patroni:latest
#
# =============================================================================

ARG BASE_IMAGE=ubuntu:22.04
ARG PGVERSION=16

# =============================================================================
# Build Stage
# =============================================================================
FROM ${BASE_IMAGE} as builder

ARG PGVERSION=16

# Set environment
ENV DEBIAN_FRONTEND=noninteractive \
    PGVERSION=${PGVERSION}

WORKDIR /build

# Copy build scripts
COPY build_scripts/ /build/build_scripts/

# Install PostgreSQL and base dependencies
RUN chmod +x /build/build_scripts/*.sh && \
    /build/build_scripts/base.sh

# Install Supabase extensions
RUN /build/build_scripts/extensions.sh

# Install Patroni with etcd support
RUN /build/build_scripts/patroni.sh

# =============================================================================
# Runtime Stage
# =============================================================================
FROM ${BASE_IMAGE}

LABEL maintainer="Supabase Patroni Project"
LABEL description="Supabase PostgreSQL with Patroni HA (etcd/consul/k8s support)"

ARG PGVERSION=16

# Set environment variables
ENV DEBIAN_FRONTEND=noninteractive \
    PGVERSION=${PGVERSION} \
    LC_ALL=en_US.UTF-8 \
    LANG=en_US.UTF-8 \
    PATH="/usr/lib/postgresql/${PGVERSION}/bin:$PATH" \
    PGHOME=/home/postgres \
    RW_DIR=/run

ENV PGROOT=${PGHOME}/pgdata \
    PGDATA=${PGHOME}/pgdata/data \
    PGLOG=${PGHOME}/pgdata/pg_log

WORKDIR ${PGHOME}

# Install runtime dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
    locales \
    gnupg \
    lsb-release \
    wget \
    curl \
    ca-certificates \
    runit \
    dumb-init \
    jq \
    python3 \
    python3-pip \
    python3-psycopg2 \
    python3-yaml \
    python3-requests \
    python3-pystache \
    python3-psutil \
    python3-etcd \
    python3-consul \
    python3-kazoo \
    python3-dnspython \
    libsodium23 \
    libcurl4 \
    libevent-2.1-7 \
    libevent-pthreads-2.1-7 \
    && rm -rf /var/lib/apt/lists/*

# Generate locales
RUN echo "en_US.UTF-8 UTF-8" >> /etc/locale.gen && \
    locale-gen en_US.UTF-8 && \
    update-locale LANG=en_US.UTF-8

# Add PostgreSQL repository and install PostgreSQL
RUN echo "deb http://apt.postgresql.org/pub/repos/apt $(lsb_release -cs)-pgdg main" > /etc/apt/sources.list.d/pgdg.list && \
    wget --quiet -O - https://www.postgresql.org/media/keys/ACCC4CF8.asc | apt-key add - && \
    apt-get update && \
    mkdir -p /etc/postgresql-common && \
    echo "create_main_cluster = false" >> /etc/postgresql-common/createcluster.conf && \
    apt-get install -y --no-install-recommends \
        "postgresql-${PGVERSION}" \
        "postgresql-contrib-${PGVERSION}" \
        "postgresql-${PGVERSION}-cron" \
        "postgresql-plpython3-${PGVERSION}" \
    && rm -rf /var/lib/apt/lists/*

# Install Patroni with all DCS backends
RUN pip3 install --no-cache-dir \
    "patroni[etcd,etcd3,consul,zookeeper,kubernetes]==4.0.4" \
    python-dateutil \
    click \
    prettytable \
    ydiff

# Copy extensions from builder stage
COPY --from=builder /usr/lib/postgresql/${PGVERSION}/lib/*.so /usr/lib/postgresql/${PGVERSION}/lib/
COPY --from=builder /usr/share/postgresql/${PGVERSION}/extension/ /usr/share/postgresql/${PGVERSION}/extension/

# Create directories and set permissions
RUN mkdir -p ${PGHOME} ${PGROOT} ${PGDATA} ${PGLOG} \
    /var/lib/patroni \
    /etc/patroni \
    /run/patroni \
    /var/run/postgresql \
    /scripts \
    /etc/runit/runsvdir/default/patroni && \
    chown -R postgres:postgres ${PGHOME} /var/lib/patroni /etc/patroni /run/patroni /var/run/postgresql /scripts && \
    chmod 0700 ${PGDATA}

# Copy scripts
COPY scripts/ /scripts/
COPY launch.sh /launch.sh
COPY runit/patroni/run /etc/runit/runsvdir/default/patroni/run
COPY runit/patroni/finish /etc/runit/runsvdir/default/patroni/finish

# Set permissions
RUN chmod +x /launch.sh /scripts/*.sh /scripts/*.py \
    /etc/runit/runsvdir/default/patroni/run \
    /etc/runit/runsvdir/default/patroni/finish && \
    chown -R postgres:postgres /scripts

# Add motd
RUN echo '\n\
===================================================\n\
  Supabase PostgreSQL with Patroni HA\n\
===================================================\n\
  PostgreSQL Version: '${PGVERSION}'\n\
  Patroni Version: 4.0.4\n\
  \n\
  Useful commands:\n\
    patronictl list          - Show cluster status\n\
    patronictl switchover    - Perform switchover\n\
    patronictl failover      - Perform failover\n\
    psql -U postgres         - Connect to PostgreSQL\n\
===================================================\n\
' > /etc/motd

# Expose ports
# 5432 - PostgreSQL
# 8008 - Patroni REST API
EXPOSE 5432 8008

# Set user (can be overridden for rootless containers)
# USER postgres

# Health check
HEALTHCHECK --interval=10s --timeout=5s --start-period=30s --retries=3 \
    CMD curl -sf http://localhost:8008/health || exit 1

# Entry point
CMD ["/bin/sh", "/launch.sh", "init"]
