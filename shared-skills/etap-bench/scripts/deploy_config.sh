#!/bin/bash
# deploy_config.sh — 모듈 config를 Etap에 배포하고 재시작한다.
# Usage: ./deploy_config.sh <config_name>
#   config_name: baseline | tcpip | vt | full
#
# 예시: ./deploy_config.sh baseline

ETAP_HOST="solution@61.79.198.110"
ETAP_PORT=12222
CONFIG_NAME=${1:?"Usage: $0 <baseline|tcpip|vt|full>"}
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CONFIG_DIR="${SCRIPT_DIR}/../configs"
CONFIG_FILE="${CONFIG_DIR}/module_${CONFIG_NAME}.xml"

if [ ! -f "$CONFIG_FILE" ]; then
    echo "ERROR: Config file not found: $CONFIG_FILE"
    echo "Available: baseline, tcpip, vt, full"
    exit 1
fi

echo "=== Deploying config: $CONFIG_NAME ==="
echo "File: $CONFIG_FILE"

# 1. config 전송
scp -P $ETAP_PORT "$CONFIG_FILE" ${ETAP_HOST}:/tmp/module.xml
if [ $? -ne 0 ]; then
    echo "ERROR: scp failed"
    exit 1
fi

# 2. 적용 및 재시작
ssh -p $ETAP_PORT $ETAP_HOST << 'EOF'
sudo cp /tmp/module.xml /etc/etap/module.xml
sudo systemctl restart etapd.service
EOF

# 3. 준비 대기
echo "Waiting for etapd..."
for i in $(seq 1 30); do
    if ssh -p $ETAP_PORT $ETAP_HOST "etapcomm etap.port_info" &>/dev/null; then
        echo "Ready (${i}s)"
        break
    fi
    sleep 1
    if [ "$i" -eq 30 ]; then
        echo "ERROR: etapd did not become ready within 30s"
        ssh -p $ETAP_PORT $ETAP_HOST "journalctl -u etapd.service -n 20"
        exit 1
    fi
done

# 4. 상태 확인
INSTANCE_COUNT=$(ssh -p $ETAP_PORT $ETAP_HOST "pgrep -c etapd")
if [ "$INSTANCE_COUNT" -ne 1 ]; then
    echo "WARNING: etapd instance count = $INSTANCE_COUNT (expected 1)"
    exit 1
fi

echo "=== Config $CONFIG_NAME deployed successfully ==="
ssh -p $ETAP_PORT $ETAP_HOST "cat /etc/etap/module.xml"
