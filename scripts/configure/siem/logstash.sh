#!/bin/bash
set -euo pipefail

BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
SCRIPTS_DIR="${BASE_DIR}/scripts"
CONFIG_DIR="${BASE_DIR}/config"

source "${SCRIPTS_DIR}/lib/logging.sh"
source "${CONFIG_DIR}/variables.sh"

log_info "Configuring Logstash"

SIEM_LOGSTASH_CONTAINER="clab-${LAB_NAME}-logstash"
SIEM_FW_CONTAINER="clab-${LAB_NAME}-SIEM_FW"
SIEM_ES_CONTAINER="clab-${LAB_NAME}-elasticsearch"

LOGSTASH_PID=$(sudo docker inspect -f '{{.State.Pid}}' ${SIEM_LOGSTASH_CONTAINER})
SIEMFW_PID=$(sudo docker inspect -f '{{.State.Pid}}' ${SIEM_FW_CONTAINER})

# --- Step 1: Network interface setup ---
log_info "Checking Logstash network interfaces..."

if ! sudo nsenter -t $LOGSTASH_PID -n ip link show eth1 &>/dev/null; then
    log_info "eth1 not found in Logstash — creating veth pair..."
    sudo ip link add veth-ls-fw type veth peer name veth-fw-ls 2>/dev/null || true
    sudo ip link set veth-ls-fw netns $LOGSTASH_PID
    sudo nsenter -t $LOGSTASH_PID -n ip link set veth-ls-fw name eth1
    if ! sudo nsenter -t $SIEMFW_PID -n ip link show eth3 &>/dev/null; then
        sudo ip link set veth-fw-ls netns $SIEMFW_PID
        sudo nsenter -t $SIEMFW_PID -n ip link set veth-fw-ls name eth3
        sudo nsenter -t $SIEMFW_PID -n ip addr add ${SIEM_FW_ETH3_IP} dev eth3 2>/dev/null || true
        sudo nsenter -t $SIEMFW_PID -n ip link set eth3 up
    else
        sudo ip link delete veth-fw-ls 2>/dev/null || true
    fi
    log_ok "veth pair created"
else
    log_info "eth1 already exists in Logstash"
fi

sudo nsenter -t $LOGSTASH_PID -n ip addr add ${SIEM_LOGSTASH_ETH1_IP} dev eth1 2>/dev/null || true
sudo nsenter -t $LOGSTASH_PID -n ip link set eth1 up
sudo nsenter -t $LOGSTASH_PID -n ip route add 10.0.3.0/24 via ${SIEM_FW_ETH3_IP%/*} dev eth1 2>/dev/null || true

echo "=== Logstash Network Configuration ==="
sudo nsenter -t $LOGSTASH_PID -n ip addr show | grep "inet " || true
sudo nsenter -t $LOGSTASH_PID -n ip route show || true

# --- Step 2: Register ES hostname in /etc/hosts ---
log_info "Registering Elasticsearch hostname..."
ES_IP=$(sudo docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' ${SIEM_ES_CONTAINER})
sudo nsenter -t $LOGSTASH_PID -m -- bash -c "grep -q elasticsearch /etc/hosts || echo '$ES_IP elasticsearch' >> /etc/hosts"
log_ok "Elasticsearch registered as $ES_IP"

# --- Step 3: Directory permissions ---
log_info "Setting up Logstash directories..."
sudo docker exec -u 0 ${SIEM_LOGSTASH_CONTAINER} bash -c '
    mkdir -p /usr/share/logstash/data /usr/share/logstash/logs
    chown -R logstash:logstash /usr/share/logstash/data /usr/share/logstash/logs
' 2>/dev/null || true

# --- Step 4: Start Logstash process ---
log_info "Starting Logstash process..."
if sudo docker exec ${SIEM_LOGSTASH_CONTAINER} ps aux 2>/dev/null | grep -q "[j]ava.*logstash"; then
    log_info "Logstash is already running"
else
    sudo docker exec -d -u logstash ${SIEM_LOGSTASH_CONTAINER} /usr/share/logstash/bin/logstash \
        --path.config /usr/share/logstash/pipeline \
        --path.settings /usr/share/logstash/config \
        --path.data /usr/share/logstash/data \
        --path.logs /usr/share/logstash/logs
    log_info "Waiting for Logstash to start (90 seconds)..."
    sleep 90
    if sudo docker exec ${SIEM_LOGSTASH_CONTAINER} ps aux 2>/dev/null | grep -q "[j]ava.*logstash"; then
        log_ok "Logstash process is running"
    else
        log_warn "Logstash may not have started"
    fi
fi

log_ok "Logstash configured"
