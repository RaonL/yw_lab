#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
source "${SCRIPT_DIR}/scripts/lib/logging.sh"

log_info "=== Manual IDS Startup Helper ==="

IDS_NODES=("clab-yw-DMZ_IDS" "clab-yw-Internal_IDS")
MAX_WAIT=120

for node in "${IDS_NODES[@]}"; do
    log_info "Processing: $node"
    
    # 1. 컨테이너가 실행 중인지 확인
    if ! docker inspect "$node" &>/dev/null; then
        log_warn "Container $node not found, skipping..."
        continue
    fi
    
    # 2. eth1 인터페이스가 생길 때까지 대기 (최대 120 초)
    log_info "Waiting for eth1 interface in $node..."
    elapsed=0
    while [ $elapsed -lt $MAX_WAIT ]; do
        if docker exec "$node" ip link show eth1 &>/dev/null 2>&1; then
            log_ok "eth1 found in $node after ${elapsed}s"
            break
        fi
        sleep 2
        elapsed=$((elapsed + 2))
        echo -n "."
    done
    echo ""
    
    if [ $elapsed -ge $MAX_WAIT ]; then
        log_error "Timeout: eth1 not found in $node after ${MAX_WAIT}s"
        continue
    fi
    
    # 3. 기존 Suricata 프로세스 정리
    log_info "Stopping any existing Suricata process..."
    docker exec "$node" pkill -9 suricata 2>/dev/null || true
    sleep 1
    
    # 4. Suricata 수동 시작 (백그라운드)
    log_info "Starting Suricata in $node..."
    docker exec -d "$node" sh -c '
        suricata -i eth1 --af-packet \
            -c /etc/suricata/suricata.yml \
            -D \
            --pidfile /var/run/suricata.pid
    '
    
    # 5. 시작 확인
    sleep 3
    if docker exec "$node" pgrep -f "suricata.*eth1" &>/dev/null; then
        log_ok "✓ Suricata started successfully in $node"
        # PID 출력
        docker exec "$node" cat /var/run/suricata.pid 2>/dev/null || true
    else
        log_error "✗ Failed to start Suricata in $node"
        log_info "Last 10 lines of container log:"
        docker logs --tail 10 "$node" 2>&1 || true
    fi
    echo ""
done

log_info "=== IDS Startup Helper Complete ==="
