ARG NODE_VERSION=16

#### Stage BASE ########################################################################################################
FROM quay.io/krist/mdnsbase:latest AS base


# Install tools, create Node-RED app and data dir, add user and set rights
RUN dnf -y install  \
        tzdata \
        curl \
        vim \
        wget \
        git \
        openssl \
        openssh \
        ca-certificates  \
    && mkdir -p /usr/src/node-red /data /config \
    && useradd --home-dir /usr/src/node-red --uid 1000 node-red \
    && chown -R node-red:root /data && chmod -R g+rwX /data \
    && chown -R node-red:root /config && chmod -R g+rwX /config \
    && chown -R node-red:root /usr/src/node-red && chmod -R g+rwX /usr/src/node-red

# Set work directory
WORKDIR /usr/src/node-red

# Setup SSH known_hosts file

COPY scripts/known_hosts.sh .
RUN ./known_hosts.sh /etc/ssh/ssh_known_hosts \ 
    && rm /usr/src/node-red/known_hosts.sh \
    && echo "PubkeyAcceptedKeyTypes +ssh-rsa" >> /etc/ssh/ssh_config

# package.json contains Node-RED NPM module and node dependencies
COPY package.json .
COPY flows.json /data

RUN dnf -y module install nodejs:16/common

#### Stage BUILD #######################################################################################################
FROM base AS build

# Install Build tools
RUN dnf -y install avahi-compat-libdns_sd-devel systemd-devel gcc-c++ '@Development tools' \
    && npm install --loglevel verbose --unsafe-perm --no-update-notifier \
    && npm uninstall node-red-node-gpio \
    && cp -R node_modules prod_node_modules

#### Stage RELEASE #####################################################################################################
FROM base AS RELEASE
ARG BUILD_DATE
ARG BUILD_VERSION
ARG BUILD_REF
ARG NODE_RED_VERSION
ARG TAG_SUFFIX=default
ARG ARCH

LABEL org.label-schema.build-date=${BUILD_DATE} \
    org.label-schema.docker.dockerfile=".docker/Dockerfile.fedora" \
    org.label-schema.license="Apache-2.0" \
    org.label-schema.name="Node-RED" \
    org.label-schema.version=${BUILD_VERSION} \
    org.label-schema.description="Low-code programming for event-driven applications." \
    org.label-schema.url="https://nodered.org" \
    org.label-schema.vcs-ref=${BUILD_REF} \
    org.label-schema.vcs-type="Git" \
    org.label-schema.vcs-url="https://github.com/node-red/node-red-docker" \
    org.label-schema.arch=${ARCH} \
    authors="Dave Conway-Jones, Nick O'Leary, James Thomas, Raymond Mouthaan"

COPY --from=build /usr/src/node-red/prod_node_modules ./node_modules

# Chown, install devtools & Clean up
RUN chown -R node-red:root /usr/src/node-red 

RUN npm config set cache /data/.npm --global

# Env variables
ENV NODE_RED_VERSION=$NODE_RED_VERSION \
    NODE_PATH=/usr/src/node-red/node_modules:/data/node_modules \
    PATH=/usr/src/node-red/node_modules/.bin:${PATH} \
    FLOWS=flows.json

# ENV NODE_RED_ENABLE_SAFE_MODE=true    # Uncomment to enable safe start mode (flows not running)
# ENV NODE_RED_ENABLE_PROJECTS=true     # Uncomment to enable projects option

COPY scripts/nodered.service /etc/systemd/system
RUN systemctl enable nodered

# Expose the listening port of node-red
EXPOSE 1880

# Add a healthcheck (default every 30 secs)
# HEALTHCHECK CMD curl http://localhost:1880/ || exit 1

CMD ["/sbin/init"]
STOPSIGNAL SIGRTMIN+3
