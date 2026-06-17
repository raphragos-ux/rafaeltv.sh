#!/bin/bash

set +e

# =========================================
# SHELL DEPLOYER BY RAFAEL R. - VMESS VERSION
# =========================================

# =========================
# COLORS
# =========================

GREEN='\033[1;32m'
RED='\033[1;31m'
YELLOW='\033[1;33m'
BLUE='\033[1;34m'
CYAN='\033[1;36m'
WHITE='\033[1;37m'
NC='\033[0m'

# =========================
# VARIABLES
# =========================

PROJECT_ID="$(gcloud config get-value project)"

REGION="us-central1"

RAND=$(openssl rand -hex 3)

CLOUD_RUN_SERVICE_NAME="rafael-$RAND"

DOMAIN="www.google.com"

BUILD_DIR=$(mktemp -d)

# Fixed Credentials
UUID="15f7e8ea-7b56-45d4-93af-31f3c592fdf1"
TROJAN_PASS="rafaeltv"

# =========================
# CLEANUP
# =========================

cleanup() {
    rm -rf "$BUILD_DIR"
}

trap cleanup EXIT

# =========================
# HEADER
# =========================

clear

echo ""
echo -e "${CYAN}=========================================${NC}"
echo -e "${GREEN}   DEPLOYER: TROJAN + VLESS + VMESS${NC}"
echo -e "${CYAN}=========================================${NC}"
echo ""

# =========================
# CHECK PROJECT
# =========================

if [ -z "$PROJECT_ID" ]; then

    echo ""
    echo -e "${RED}ERROR: No Google Cloud project set.${NC}"
    echo ""
    echo "Run:"
    echo "gcloud config set project YOUR_PROJECT_ID"
    echo ""

    exit 1
fi

# =========================
# ENABLE REQUIRED APIS
# =========================

echo ""
echo -e "${CYAN}=========================================${NC}"
echo -e "${GREEN}        ENABLING REQUIRED APIS${NC}"
echo -e "${CYAN}=========================================${NC}"
echo ""

gcloud services enable \
run.googleapis.com \
cloudbuild.googleapis.com \
artifactregistry.googleapis.com

# =========================
# BILLING SETTINGS
# =========================

echo ""
echo -e "${CYAN}=========================================${NC}"
echo -e "${GREEN}          BILLING SETTINGS${NC}"
echo -e "${CYAN}=========================================${NC}"
echo ""

echo -e "${WHITE}1) REQUEST-BASED${NC}"
echo "   ( CHARGED ONLY WHEN PROCESSING REQUESTS )"
echo "   ( CPU IS LIMITED OUTSIDE OF REQUESTS )"
echo ""

echo -e "${WHITE}2) INSTANCE-BASED${NC} ✅ RECOMMENDED"
echo "   ( CHARGED FOR THE ENTIRE LIFECYCLE OF INSTANCES )"
echo "   ( FULL CPU FOR STABLE CONNECTION )"
echo ""

while true; do

    read -p "Select Billing Type [1-2]: " BILLING_CHOICE

    case $BILLING_CHOICE in

        1)
            BILLING_MODE="request"
            break
        ;;

        2)
            BILLING_MODE="instance"
            break
        ;;

        *)
            echo ""
            echo -e "${RED}PLEASE PUT RIGHT VALUE${NC}"
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
echo ""
echo "1) 512Mi              1) 1vCPU"
echo "2) 1Gi                2) 2vCPU"
echo "3) 2Gi                3) 4vCPU ✅ RECOMMENDED"
echo "4) 4Gi                4) 6vCPU"
echo "5) 8Gi                5) 8vCPU"
echo "6) 16Gi"
echo "7) 32Gi"
echo ""

echo -e "${YELLOW}SUGGESTION:${NC}"
echo "2GiB x 2vCPU / MIN 0 - MAX 2"
echo ""

while true; do

    read -p "Select Memory [1-7]: " MEMORY_CHOICE

    case $MEMORY_CHOICE in

        1) MEMORY="512Mi"; break ;;
        2) MEMORY="1Gi"; break ;;
        3) MEMORY="2Gi"; break ;;
        4) MEMORY="4Gi"; break ;;
        5) MEMORY="8Gi"; break ;;
        6) MEMORY="16Gi"; break ;;
        7) MEMORY="32Gi"; break ;;
        *) echo -e "${RED}PLEASE PUT RIGHT VALUE${NC}"; echo "" ;;

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
        *) echo -e "${RED}PLEASE PUT RIGHT VALUE${NC}"; echo "" ;;

    esac

done

echo ""
echo -e "${GREEN}Selected Billing:${NC} $BILLING_MODE"
echo -e "${GREEN}Selected Memory:${NC} $MEMORY"
echo -e "${GREEN}Selected vCPU:${NC} $CPU"
echo ""

# =========================
# FIXED VALUES
# =========================

CONCURRENCY="1000"
TIMEOUT="3600"

echo -e "${GREEN}Concurrency:${NC} $CONCURRENCY"
echo -e "${GREEN}Timeout:${NC} $TIMEOUT"
echo ""

# =========================
# INSTANCE RULES
# =========================

SPECIAL_MODE="false"
[ "$MEMORY" = "4Gi" ] && [ "$CPU" = "4" ] && SPECIAL_MODE="true"

# =========================
# MIN INSTANCES
# =========================

echo -e "${GREEN}Min Instances:${NC} Allowed 0 - 1 | Default: 0"
while true; do
    read -p "Enter Min Instances: " MIN_INST
    MIN_INST=${MIN_INST:-0}
    [[ "$MIN_INST" =~ ^[01]$ ]] && break
    echo -e "${RED}PLEASE PUT RIGHT VALUE${NC}"
done
echo ""

# =========================
# MAX INSTANCES
# =========================

if [ "$SPECIAL_MODE" = "true" ]; then
    echo -e "${GREEN}Max Instances:${NC} SPECIAL MODE | Allowed 1 - 4 | Default: 2"
    while true; do
        read -p "Enter Max Instances: " MAX_INST
        MAX_INST=${MAX_INST:-2}
        [[ "$MAX_INST" =~ ^[1-4]$ ]] && break
        echo -e "${RED}PLEASE PUT RIGHT VALUE${NC}"
    done
else
    echo -e "${GREEN}Max Instances:${NC} Allowed 0 - 2 | Default: 2"
    while true; do
        read -p "Enter Max Instances: " MAX_INST
        MAX_INST=${MAX_INST:-2}
        [[ "$MAX_INST" =~ ^[0-2]$ ]] && break
        echo -e "${RED}PLEASE PUT RIGHT VALUE${NC}"
    done
fi
echo ""

# =========================
# CREATE DIRECTORY
# =========================

mkdir -p "$BUILD_DIR"
cd "$BUILD_DIR" || exit 1

# =========================
# ✅ UPDATED CONFIG.JSON (WITH VMESS)
# =========================

cat > config.json <<EOF
{
  "log": {
    "loglevel": "warning"
  },
  "inbounds": [
    {
      "tag": "trojan-ws",
      "port": 10001,
      "listen": "127.0.0.1",
      "protocol": "trojan",
      "settings": {
        "clients": [{"password": "$TROJAN_PASS"}]
      },
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
        "clients": [{"id": "$UUID", "level": 0, "email": "vless@rafael"}],
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
        "clients": [{"id": "$UUID", "alterId": 0, "level": 0, "email": "vmess@rafael"}]
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

# =========================
# ✅ UPDATED NGINX.CONF
# =========================

cat > nginx.conf <<EOF
worker_processes auto;
worker_rlimit_nofile 200000;

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

    gzip on;
    gzip_comp_level 5;
    gzip_types text/plain text/css application/json application/javascript;

    map \$request_uri \$backend_host { default $DOMAIN; }
    map \$http_upgrade \$connection_upgrade { default upgrade; '' close; }

    server {
        listen 8080;
        http2 on;

        location / {
            proxy_ssl_server_name on;
            proxy_ssl_protocols TLSv1.2 TLSv1.3;
            proxy_pass https://\$backend_host;
            proxy_set_header Host \$backend_host;
            proxy_set_header Referer https://www.google.com/;
            proxy_set_header Origin https://www.cloudflare.com/;
            proxy_set_header X-Real-IP \$remote_addr;
            proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto \$scheme;
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
            proxy_buffering off;
            proxy_read_timeout 3600s;
        }

        # ✅ NEW VMESS LOCATION
        location /vmess-rafael {
            proxy_pass http://127.0.0.1:10003;
            proxy_http_version 1.1;
            proxy_set_header Upgrade \$http_upgrade;
            proxy_set_header Connection \$connection_upgrade;
            proxy_set_header Host \$host;
            proxy_buffering off;
            proxy_read_timeout 3600s;
        }
    }
}
EOF

# =========================
# ENTRYPOINT.SH
# =========================

cat > entrypoint.sh <<EOF
#!/bin/sh
set -e
/usr/local/bin/xray run -c /etc/xray.json &
sleep 5
exec /usr/local/openresty/bin/openresty -g 'daemon off;'
EOF

chmod +x entrypoint.sh

# =========================
# DOCKERFILE
# =========================

cat > Dockerfile <<EOF
FROM alpine:3.20 AS xray-bin
RUN apk add --no-cache curl unzip ca-certificates
WORKDIR /tmp
RUN curl -sL https://github.com/XTLS/Xray-core/releases/latest/download/Xray-linux-64.zip -o xray.zip \\
    && unzip xray.zip xray \\
    && chmod +x xray \\
    && mv xray /usr/local/bin/

FROM openresty/openresty:alpine-fat
RUN apk add --no-cache ca-certificates tzdata
COPY --from=xray-bin /usr/local/bin/xray /usr/local/bin/xray
COPY config.json /etc/xray.json
COPY nginx.conf /usr/local/openresty/nginx/conf/nginx.conf
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh
EXPOSE 8080
CMD ["/entrypoint.sh"]
EOF

# =========================
# BUILD IMAGE
# =========================

echo ""
echo -e "${CYAN}=========================================${NC}"
echo -e "${GREEN}          BUILDING IMAGE${NC}"
echo -e "${CYAN}=========================================${NC}"
echo ""

gcloud builds submit \
  --tag gcr.io/$PROJECT_ID/$CLOUD_RUN_SERVICE_NAME \
  . \
  --quiet

# =========================
# DEPLOY CLOUD RUN
# =========================

if [ "$BILLING_MODE" = "instance" ]; then
    BILLING_FLAGS="--no-cpu-throttling --cpu-boost"
else
    BILLING_FLAGS="--cpu-throttling"
fi

echo ""
echo -e "${CYAN}=========================================${NC}"
echo -e "${GREEN}         DEPLOYING CLOUD RUN${NC}"
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
  $BILLING_FLAGS \
  --quiet

# =========================
# CLOUD RUN URL
# =========================

CLOUD_RUN_URL=$(gcloud run services describe $CLOUD_RUN_SERVICE_NAME \
  --region=$REGION \
  --format='value(status.url)' | sed 's|https://||')

# =========================
# OUTPUT
# =========================

echo ""
echo -e "${CYAN}=========================================${NC}"
echo -e "${GREEN}✅ DEPLOYMENT COMPLETE${NC}"
echo -e "${CYAN}=========================================${NC}"
echo ""

echo -e "${GREEN}SERVICE NAME:${NC} $CLOUD_RUN_SERVICE_NAME"
echo ""

echo -e "${CYAN}=========================================${NC}"
echo -e "${GREEN}TROJAN WS${NC}"
echo -e "${CYAN}=========================================${NC}"
echo "Address: $CLOUD_RUN_URL"
echo "Port: 443"
echo "Password: $TROJAN_PASS"
echo "Path: /trojan-rafael?ed=2180"
echo "TLS: Enabled"
echo ""

echo -e "${CYAN}=========================================${NC}"
echo -e "${GREEN}VLESS WS${NC}"
echo -e "${CYAN}=========================================${NC}"
echo "Address: $CLOUD_RUN_URL"
echo "Port: 443"
echo "UUID: $UUID"
echo "Encryption: none"
echo "Path: /vless-rafael?ed=2180"
echo "TLS: Enabled"
echo ""

echo -e "${CYAN}=========================================${NC}"
echo -e "${GREEN}VMESS WS ✅ NEW${NC}"
echo -e "${CYAN}=========================================${NC}"
echo "Address: $CLOUD_RUN_URL"
echo "Port: 443"
echo "UUID: $UUID"
echo "Alter ID: 0"
echo "Security: auto"
echo "Network: ws"
echo "Path: /vmess-rafael?ed=2180"
echo "TLS: Enabled"
echo ""

echo -e "${CYAN}=========================================${NC}"
echo -e "${GREEN}DONE${NC}"
echo -e "${CYAN}=========================================${NC}"
