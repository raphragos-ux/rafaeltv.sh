#!/bin/bash

set -euo pipefail

# =========================================
# SHELL DEPLOYER BY RAFAEL R. - ERROR FIXED
# =========================================

# =========================
# COLORS
# =========================
GREEN='\033[1;32m'
RED='\033[1;31m'
YELLOW='\033[1;33m'
CYAN='\033[1;36m'
WHITE='\033[1;37m'
NC='\033[0m'

# =========================
# VARIABLES
# =========================
PROJECT_ID="$(gcloud config get-value project 2>/dev/null || echo "")"
REGION="us-central1"
RAND=$(openssl rand -hex 3)
CLOUD_RUN_SERVICE_NAME="rafael-$RAND"
DOMAIN="www.google.com"
BUILD_DIR=$(mktemp -d)

# Credentials
UUID="15f7e8ea-7b56-45d4-93af-31f3c592fdf1"
TROJAN_PASS="rafaeltv"

trap 'rm -rf "$BUILD_DIR"' EXIT

# =========================
# HEADER
# =========================
clear
echo ""
echo -e "${CYAN}=========================================${NC}"
echo -e "${GREEN}   DEPLOYER: TROJAN + VLESS + VMESS${NC}"
echo -e "${GREEN}        NO MORE ERRORS${NC}"
echo -e "${CYAN}=========================================${NC}"
echo ""

# =========================
# CHECK PROJECT
# =========================
if [ -z "$PROJECT_ID" ]; then
    echo -e "${RED}❌ ERROR: No Google Cloud project set.${NC}"
    echo "Run first: gcloud config set project YOUR_PROJECT_ID"
    exit 1
fi

# =========================
# ENABLE APIS
# =========================
echo -e "${CYAN}➡️ Enabling required APIs...${NC}"
gcloud services enable \
    run.googleapis.com \
    cloudbuild.googleapis.com \
    artifactregistry.googleapis.com \
    --quiet

# =========================
# BILLING SETTINGS
# =========================
echo ""
echo -e "${CYAN}=========================================${NC}"
echo -e "${GREEN}          BILLING SETTINGS${NC}"
echo -e "${CYAN}=========================================${NC}"
echo ""

echo -e "${WHITE}1) REQUEST-BASED${NC}"
echo "   ( Charged only when used, limited CPU )"
echo ""
echo -e "${WHITE}2) INSTANCE-BASED${NC} ✅ RECOMMENDED"
echo "   ( Stable, full CPU, no throttling )"
echo ""

while true; do
    read -p "Select Billing Type [1-2]: " BILLING_CHOICE
    case $BILLING_CHOICE in
        1)
            BILLING_MODE="request"
            BILL_FLAGS="--cpu-throttling"
            break
            ;;
        2)
            BILLING_MODE="instance"
            BILL_FLAGS="--no-cpu-throttling --cpu-boost"
            break
            ;;
        *)
            echo -e "${RED}⚠️ Enter only 1 or 2${NC}"
            echo ""
            ;;
    esac
done

# =========================
# RESOURCE SETTINGS
# =========================
echo ""
echo -e "${CYAN}=========================================${NC}"
echo -e "${GREEN}      CLOUD RUN RESOURCE SETTINGS${NC}"
echo -e "${CYAN}=========================================${NC}"
echo ""

echo "MEMORY                vCPU"
echo "1) 512Mi              1) 1vCPU"
echo "2) 1Gi                2) 2vCPU"
echo "3) 2Gi                3) 4vCPU"
echo "4) 4Gi                4) 6vCPU"
echo "5) 8Gi                5) 8vCPU"
echo ""

while true; do
    read -p "Select Memory [1-5]: " MEMORY_CHOICE
    case $MEMORY_CHOICE in
        1) MEMORY="512Mi"; break ;;
        2) MEMORY="1Gi"; break ;;
        3) MEMORY="2Gi"; break ;;
        4) MEMORY="4Gi"; break ;;
        5) MEMORY="8Gi"; break ;;
        *) echo -e "${RED}⚠️ Enter valid number${NC}"; echo "" ;;
    esac
done

while true; do
    read -p "Select vCPU [1-5]: " CPU_CHOICE
    case $CPU_CHOICE in
        1) CPU="1"; break ;;
        2) CPU="2"; break ;;
        3) CPU="4"; break ;;
        4) CPU="6"; break ;;
        5) CPU="8"; break ;;
        *) echo -e "${RED}⚠️ Enter valid number${NC}"; echo "" ;;
    esac
done

echo ""
echo -e "${GREEN}✅ Selected:${NC} $MEMORY | $CPU | $BILLING_MODE"
echo ""

# =========================
# FIXED VALUES
# =========================
CONCURRENCY="1000"
TIMEOUT="3600"
MIN_INST="0"
MAX_INST="2"

# =========================
# CREATE FILES
# =========================
mkdir -p "$BUILD_DIR"
cd "$BUILD_DIR" || exit 1

# ✅ CONFIG.JSON
cat > config.json <<EOF
{
  "log": {"loglevel": "warning"},
  "inbounds": [
    {
      "tag": "trojan-ws",
      "port": 10001,
      "listen": "127.0.0.1",
      "protocol": "trojan",
      "settings": {"clients": [{"password": "$TROJAN_PASS"}]},
      "sniffing": {"enabled": true, "destOverride": ["http", "tls"]},
      "streamSettings": {
        "network": "ws",
        "wsSettings": {"path": "/trojan-rafael?ed=2180"}
      }
    },
    {
      "tag": "vless-ws",
      "port": 10002,
      "listen": "127.0.0.1",
      "protocol": "vless",
      "settings": {
        "clients": [{"id": "$UUID", "level": 0}],
        "decryption": "none"
      },
      "sniffing": {"enabled": true, "destOverride": ["http", "tls"]},
      "streamSettings": {
        "network": "ws",
        "wsSettings": {"path": "/vless-rafael?ed=2180"}
      }
    },
    {
      "tag": "vmess-ws",
      "port": 10003,
      "listen": "127.0.0.1",
      "protocol": "vmess",
      "settings": {
        "clients": [{"id": "$UUID", "alterId": 0, "security": "auto"}]
      },
      "sniffing": {"enabled": true, "destOverride": ["http", "tls"]},
      "streamSettings": {
        "network": "ws",
        "wsSettings": {"path": "/vmess-rafael?ed=2180"}
      }
    }
  ],
  "outbounds": [{"protocol": "freedom", "tag": "direct"}]
}
EOF

# ✅ NGINX.CONF
cat > nginx.conf <<EOF
worker_processes auto;
worker_rlimit_nofile 65535;

events {
    worker_connections 65535;
    multi_accept on;
}

http {
    sendfile on;
    tcp_nopush on;
    tcp_nodelay on;
    keepalive_timeout 3600;
    keepalive_requests 100000;
    client_max_body_size 0;

    proxy_connect_timeout 300s;
    proxy_send_timeout 3600s;
    proxy_read_timeout 3600s;
    proxy_buffering off;
    proxy_request_buffering off;

    server_tokens off;

    map \$http_upgrade \$connection_upgrade {
        default upgrade;
        '' close;
    }

    server {
        listen 8080;
        server_name _;

        location / {
            proxy_ssl_server_name on;
            proxy_ssl_protocols TLSv1.2 TLSv1.3;
            proxy_pass https://$DOMAIN;
            proxy_set_header Host $DOMAIN;
            proxy_set_header Referer https://www.google.com/;
            proxy_set_header Origin https://www.cloudflare.com/;
            proxy_set_header X-Forwarded-Proto \$scheme;
            proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        }

        location /trojan-rafael {
            proxy_pass http://127.0.0.1:10001;
            proxy_http_version 1.1;
            proxy_set_header Upgrade \$http_upgrade;
            proxy_set_header Connection \$connection_upgrade;
            proxy_set_header Host \$host;
            proxy_read_timeout 3600s;
        }

        location /vless-rafael {
            proxy_pass http://127.0.0.1:10002;
            proxy_http_version 1.1;
            proxy_set_header Upgrade \$http_upgrade;
            proxy_set_header Connection \$connection_upgrade;
            proxy_set_header Host \$host;
            proxy_read_timeout 3600s;
        }

        location /vmess-rafael {
            proxy_pass http://127.0.0.1:10003;
            proxy_http_version 1.1;
            proxy_set_header Upgrade \$http_upgrade;
            proxy_set_header Connection \$connection_upgrade;
            proxy_set_header Host \$host;
            proxy_read_timeout 3600s;
        }
    }
}
EOF

# ✅ ENTRYPOINT
cat > entrypoint.sh <<EOF
#!/bin/sh
set -e
/usr/local/bin/xray run -c /etc/xray/config.json &
sleep 5
exec /usr/local/openresty/bin/openresty -g 'daemon off;'
EOF
chmod +x entrypoint.sh

# ✅ DOCKERFILE - FIXED XRAY DOWNLOAD
cat > Dockerfile <<EOF
FROM alpine:3.21 AS xray-bin
RUN apk add --no-cache curl unzip ca-certificates
WORKDIR /tmp
# Gumamit ng direkta at matatag na link sa halip na "latest"
RUN curl -sL -o xray.zip https://github.com/XTLS/Xray-core/releases/download/v25.2.1/Xray-linux-64.zip \
    && unzip xray.zip xray \
    && chmod +x xray \
    && mv xray /usr/local/bin/

FROM openresty/openresty:alpine
RUN apk add --no-cache ca-certificates tzdata
COPY --from=xray-bin /usr/local/bin/xray /usr/local/bin/xray
COPY config.json /etc/xray/config.json
COPY nginx.conf /usr/local/openresty/nginx/conf/nginx.conf
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh
EXPOSE 8080
CMD ["/entrypoint.sh"]
EOF

# =========================
# BUILD & DEPLOY
# =========================
echo ""
echo -e "${CYAN}=========================================${NC}"
echo -e "${GREEN}          BUILDING IMAGE${NC}"
echo -e "${CYAN}=========================================${NC}"
echo ""

gcloud builds submit \
  --tag gcr.io/$PROJECT_ID/$CLOUD_RUN_SERVICE_NAME \
  --quiet

echo ""
echo -e "${CYAN}=========================================${NC}"
echo -e "${GREEN}         DEPLOYING TO CLOUD RUN${NC}"
echo -e "${CYAN}=========================================${NC}"
echo ""

gcloud run deploy $CLOUD_RUN_SERVICE_NAME \
  --image gcr.io/$PROJECT_ID/$CLOUD_RUN_SERVICE_NAME \
  --platform managed \
  --region $REGION \
  --allow-unauthenticated \
  --port 8080 \
  --memory $MEMORY \
  --cpu $CPU \
  --concurrency $CONCURRENCY \
  --timeout $TIMEOUT \
  --min-instances $MIN_INST \
  --max-instances $MAX_INST \
  --execution-environment gen2 \
  $BILL_FLAGS \
  --quiet

# =========================
# GENERATE LINKS
# =========================
CLOUD_RUN_URL=$(gcloud run services describe $CLOUD_RUN_SERVICE_NAME \
  --region=$REGION \
  --format='value(status.url)' 2>/dev/null || echo "ERROR")

if [ "$CLOUD_RUN_URL" = "ERROR" ]; then
    echo -e "${RED}❌ Failed to get service URL${NC}"
    exit 1
fi

DOMAIN_ONLY=$(echo "$CLOUD_RUN_URL" | sed 's|https://||')

# Base64 for VMESS
VMESS_RAW='{"v":"2","ps":"VMESS-Rafael","add":"'$DOMAIN_ONLY'","port":"443","id":"'$UUID'","aid":"0","scy":"auto","net":"ws","type":"none","host":"'$DOMAIN'","path":"/vmess-rafael?ed=2180","tls":"tls","sni":"'$DOMAIN'"}'
VMESS_B64=$(echo -n "$VMESS_RAW" | base64 -w 0)

# =========================
# FINAL OUTPUT
# =========================
echo ""
echo -e "${CYAN}=========================================${NC}"
echo -e "${GREEN}✅ DEPLOYMENT SUCCESSFUL${NC}"
echo -e "${CYAN}=========================================${NC}"
echo ""

echo -e "${GREEN}🔗 SERVICE URL:${NC} $CLOUD_RUN_URL"
echo ""

echo -e "${CYAN}--- TROJAN WS ---${NC}"
echo "Link: trojan://$TROJAN_PASS@$DOMAIN_ONLY:443?path=%2Ftrojan-rafael%3Fed%3D2180&security=tls&host=$DOMAIN&type=ws&sni=$DOMAIN#Trojan-Rafael"
echo ""

echo -e "${CYAN}--- VLESS WS ---${NC}"
echo "Link: vless://$UUID@$DOMAIN_ONLY:443?path=%2Fvless-rafael%3Fed%3D2180&security=tls&host=$DOMAIN&type=ws&encryption=none&sni=$DOMAIN#VLESS-Rafael"
echo ""

echo -e "${CYAN}--- VMESS WS ---${NC}"
echo "Link: vmess://$VMESS_B64"
echo ""

echo -e "${CYAN}=========================================${NC}"
echo -e "${GREEN}DONE! COPY & USE LINKS ABOVE${NC}"
echo -e "${CYAN}=========================================${NC}"
