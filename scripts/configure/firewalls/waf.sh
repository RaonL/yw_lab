#!/bin/bash
set -euo pipefail

BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
SCRIPTS_DIR="${BASE_DIR}/scripts"
CONFIG_DIR="${BASE_DIR}/config"

source "${SCRIPTS_DIR}/lib/logging.sh"
source "${CONFIG_DIR}/variables.sh"

log_info "Configuring WAF with Full Logging Pipeline"

WAF_CONTAINER="clab-${LAB_NAME}-Proxy_WAF"

sudo docker exec -u 0 -i \
    -e DMZ_WAF_ETH3_IP="${DMZ_WAF_ETH3_IP}" \
    -e SUBNET_BACKEND="${SUBNET_BACKEND}" \
    -e SIEM_FW_ETH9_IP="${SIEM_FW_ETH9_IP}" \
    "${WAF_CONTAINER}" bash << 'innerEOF'
set -e

# 1. Elastic 레포지토리 등록 및 필수 도구 설치
echo "[1/4] Setting up repositories and tools..."
apt-get update -qq
apt-get install -y curl gnupg iproute2 procps 2>&1 | tail -5

if [ ! -f /etc/apt/sources.list.d/elastic-8.x.list ]; then
    curl -fsSL https://artifacts.elastic.co/GPG-KEY-elasticsearch | gpg --dearmor -o /usr/share/keyrings/elastic-archive-keyring.gpg
    echo "deb [signed-by=/usr/share/keyrings/elastic-archive-keyring.gpg] https://artifacts.elastic.co/packages/8.x/apt stable main" | tee /etc/apt/sources.list.d/elastic-8.x.list
    apt-get update -qq
fi

apt-get install -y filebeat 2>&1 | tail -5

# 2. Nginx 로그 파일 실체화
echo "[2/4] Fixing log files..."
rm -f /var/log/nginx/error.log
touch /var/log/nginx/error.log
chown nginx:nginx /var/log/nginx/error.log
nginx -s reload || true

# 3. Filebeat 설정
echo "[3/4] Configuring Filebeat..."
cat > /etc/filebeat/filebeat.yml << FILEBEAT_CONFIG
filebeat.inputs:
- type: log
  enabled: true
  paths:
    - /var/log/nginx/error.log
    - /var/log/modsecurity/modsec_audit.log
  fields:
    log_type: waf_attack
    firewall: waf
  fields_under_root: true

output.logstash:
  hosts: ["172.20.20.16:5044"]

path.data: /var/lib/filebeat
logging.level: warning
FILEBEAT_CONFIG

chmod 644 /etc/filebeat/filebeat.yml

# 4. Filebeat 실행
echo "[4/4] Starting Filebeat..."
pkill filebeat || true
nohup filebeat -e -c /etc/filebeat/filebeat.yml > /var/log/filebeat.log 2>&1 &

# 5. 네트워크 설정 (ip 명령어가 설치된 후 실행)
ip addr add "${DMZ_WAF_ETH3_IP}" dev eth3 || true
ip link set eth3 up
ip route add "${SUBNET_BACKEND}" via "${SIEM_FW_ETH9_IP%/*}" dev eth3 || true

echo "[DONE] WAF Logging Pipeline is Active"
innerEOF

log_ok "WAF Configuration and Logging Pipeline Restored"
