#!/bin/bash

# ==========================================
# 1. 自定义配置区
# ==========================================
# Telegram 配置
TG_TOKEN="8526087156:AAHR5forb44MA061r0zgcPMiGtkkxHD5K6o"
TG_CHAT_ID="6303873752"

# 节点配置
TROJAN_PORT=52255
TROJAN_PASSWORD="MyTrojanPass123"
SNI_DOMAIN="otheve.beacon.qq.com"
DOH_URL="https://223.5.5.5/dns-query"

# ==========================================
# 2. 基础环境安装
# ==========================================
echo "正在安装基础环境..."
sudo apt-get update
sudo apt-get install -y ca-certificates curl jq openssl docker.io docker-compose
sudo systemctl enable --now docker

# 开启内核转发
sudo sysctl -w net.ipv4.ip_forward=1
echo "net.ipv4.ip_forward=1" | sudo tee -a /etc/sysctl.conf

# ==========================================
# 3. 准备自签名证书
# ==========================================
mkdir -p ~/trojan_isolated/cert
cd ~/trojan_isolated

openssl req -x509 -nodes -days 3650 -newkey rsa:2048 \
-keyout ./cert/server.key -out ./cert/server.crt \
-subj "/CN=$SNI_DOMAIN"

# ==========================================
# 4. 生成 sing-box 配置
# ==========================================
cat <<EOT > config.json
{
  "log": { "level": "info", "timestamp": true },
  "dns": {
    "servers": [{ "tag": "dns-remote", "address": "$DOH_URL", "detour": "direct" }],
    "strategy": "ipv4_only"
  },
  "inbounds": [
    {
      "type": "trojan",
      "tag": "trojan-in",
      "listen": "::",
      "listen_port": $TROJAN_PORT,
      "users": [{ "name": "user1", "password": "$TROJAN_PASSWORD" }],
      "tls": {
        "enabled": true,
        "server_name": "$SNI_DOMAIN",
        "certificate_path": "/etc/sing-box/cert/server.crt",
        "key_path": "/etc/sing-box/cert/server.key"
      }
    }
  ],
  "outbounds": [{ "type": "direct", "tag": "direct" }]
}
EOT

# 写入 docker-compose.yml
cat <<EOT > docker-compose.yml
version: '3'
services:
  sing-box:
    image: ghcr.io/sagernet/sing-box:latest
    container_name: trojan-isolated
    restart: always
    ports:
      - "$TROJAN_PORT:$TROJAN_PORT/tcp"
      - "$TROJAN_PORT:$TROJAN_PORT/udp"
    volumes:
      - ./config.json:/etc/sing-box/config.json
      - ./cert:/etc/sing-box/cert
    command: -D /var/lib/sing-box -c /etc/sing-box/config.json run
EOT

# ==========================================
# 5. 启动服务
# ==========================================
if docker compose version >/dev/null 2>&1; then
    docker compose down 2>/dev/null && docker compose up -d
else
    docker-compose down 2>/dev/null && docker-compose up -d
fi

# ==========================================
# 6. 生成链接与推送
# ==========================================
IP=$(curl -s https://api64.ipify.org)
RAW_LINK="trojan://$TROJAN_PASSWORD@$IP:$TROJAN_PORT?sni=$SNI_DOMAIN&allowInsecure=1#SingBox_Trojan_$IP"

# VPS 本地终端输出完整信息
echo "-------------------------------------------------------"
echo "✅ 部署完成！"
echo "本地留存链接: $RAW_LINK"
echo "-------------------------------------------------------"

# Telegram 只发送链接
echo "正在推送链接至 Telegram..."
RESPONSE=$(curl -s -X POST "https://api.telegram.org/bot$TG_TOKEN/sendMessage" \
    --data-urlencode "chat_id=$TG_CHAT_ID" \
    --data-urlencode "text=$RAW_LINK")

if echo "$RESPONSE" | grep -q '"ok":true'; then
    echo "✅ 推送成功！"
else
    echo "❌ 推送失败，详情: $RESPONSE"
fi