ARG NODE_VERSION=22.21.0

# ==============================================================================
# STAGE 1: Builder
# ==============================================================================
FROM node:${NODE_VERSION}-alpine AS builder

WORKDIR /app

# 安装字体和图像处理依赖
RUN apk --no-cache add --virtual .build-deps-fonts msttcorefonts-installer fontconfig && \
    update-ms-fonts && \
    fc-cache -f && \
    apk del .build-deps-fonts && \
    find /usr/share/fonts/truetype/msttcorefonts/ -type l -exec unlink {} \;

# 添加 Alpine v3.22 源并安装依赖
RUN echo "https://dl-cdn.alpinelinux.org/alpine/v3.22/main" >> /etc/apk/repositories && \
    echo "https://dl-cdn.alpinelinux.org/alpine/v3.22/community" >> /etc/apk/repositories && \
    apk update && \
    apk add --no-cache libxml2 && \
    apk add --no-cache \
        git \
        openssh \
        openssl \
        graphicsmagick \
        tini \
        tzdata \
        ca-certificates \
        libc6-compat \
        jq \
        python3 \
        py3-pip \
        curl \
        wget \
        build-base

# 安装 full-icu 和 pnpm
RUN npm install -g full-icu@1.5.0 pnpm

# 拷贝源码并安装依赖
COPY . .

# 安装依赖并构建 CLI（使用 turbo）
RUN pnpm install && pnpm turbo run build --filter=cli...

# 安装 pip 并绕过 PEP 668
COPY requirements.txt /home/node/requirements.txt
RUN curl -sS https://bootstrap.pypa.io/get-pip.py -o get-pip.py && \
    python3 get-pip.py --break-system-packages && \
    rm get-pip.py && \
    pip3 install --no-cache-dir -r /home/node/requirements.txt --break-system-packages && \
    pip3 cache purge

# ==============================================================================
# STAGE 2: Runtime
# ==============================================================================
FROM node:${NODE_VERSION}-alpine

COPY --from=builder / /

WORKDIR /home/node

ENV NODE_ICU_DATA=/usr/local/lib/node_modules/full-icu
ENV N8N_ENFORCE_SETTINGS_FILE_PERMISSIONS=true \
    N8N_RUNNERS_ENABLED=true \
    N8N_PROXY_HOPS=1

# 修复权限问题
RUN mkdir -p /home/node/.n8n && chown -R node:node /home/node/.n8n

USER node

VOLUME ["/home/node/.n8n"]

EXPOSE 5678

ENTRYPOINT ["tini", "--"]
CMD ["node", "/app/packages/cli/dist/server.js"]
