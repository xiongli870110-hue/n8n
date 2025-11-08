# -------- STAGE 1: 构建阶段 --------
FROM node:18-alpine AS builder

WORKDIR /app

# 安装系统依赖（支持 Python 节点）
RUN apk add --no-cache python3 py3-pip curl wget

# 安装 pnpm
RUN npm install -g pnpm

# 拷贝源码（官方 monorepo）
COPY . .

# 安装依赖并构建
RUN pnpm install && pnpm build

# -------- STAGE 2: 运行阶段 --------
FROM node:18-alpine

ARG N8N_VERSION=custom
LABEL maintainer="rakersfu <furuijun2025@gmail.com>"
LABEL org.opencontainers.image.title="n8n-custom"
LABEL org.opencontainers.image.description="Custom n8n build from official source with Python support"
LABEL org.opencontainers.image.version=$N8N_VERSION

ENV N8N_ENFORCE_SETTINGS_FILE_PERMISSIONS=true \
    N8N_RUNNERS_ENABLED=true \
    N8N_PROXY_HOPS=1

WORKDIR /app

# 安装系统依赖（支持 Python 节点）
RUN apk add --no-cache python3 py3-pip curl wget tini

# 使用 get-pip.py 安装 pip 并绕过 PEP 668
COPY requirements.txt /home/node/requirements.txt
RUN curl -sS https://bootstrap.pypa.io/get-pip.py -o get-pip.py && \
    python3 get-pip.py --break-system-packages && \
    rm get-pip.py && \
    pip3 install --no-cache-dir -r /home/node/requirements.txt --break-system-packages && \
    pip3 cache purge

# 拷贝构建产物和依赖
COPY --from=builder /app/packages/cli/dist ./packages/cli/dist
COPY --from=builder /app/packages/cli/package.json ./packages/cli/package.json
COPY --from=builder /app/packages/workflow ./packages/workflow
COPY --from=builder /app/packages/nodes-base ./packages/nodes-base
COPY --from=builder /app/node_modules ./node_modules

# 修复权限问题（避免挂载目录报错）
RUN mkdir -p /home/node/.n8n && chown -R node:node /home/node/.n8n

USER node

VOLUME ["/home/node/.n8n"]

EXPOSE 5678

ENTRYPOINT ["tini", "--"]
CMD ["node", "packages/cli/dist/server.js"]
