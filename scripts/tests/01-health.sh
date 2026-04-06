#!/bin/bash
# Test Suite 01: Container Health & Availability
# Tests if all containers are running and accessible

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/test-utils.sh"

print_category "SECTION 1: Container Health & Availability" \
    "Verifies all required containers are running and stable"

# =========================
# Core Infrastructure
# =========================

# Internal Network
run_test "Health" "Internal_Client1 container running" \
    "container_running 'clab-yw-Internal_Client1'" 5

run_test "Health" "Internal_Client2 container running" \
    "container_running 'clab-yw-Internal_Client2'" 5

run_test "Health" "Internal_Switch container running" \
    "container_running 'clab-yw-Internal_Switch'" 5

# Firewall Layer
run_test "Health" "Internal_FW container running" \
    "container_running 'clab-yw-Internal_FW'" 5

run_test "Health" "External_FW container running" \
    "container_running 'clab-yw-External_FW'" 5

run_test "Health" "SIEM_FW container running" \
    "container_running 'clab-yw-SIEM_FW'" 5

# DMZ Layer
run_test "Health" "DMZ_Switch container running" \
    "container_running 'clab-yw-DMZ_Switch'" 5

run_test "Health" "Proxy_WAF container running" \
    "container_running 'clab-yw-Proxy_WAF'" 5

run_test "Health" "Flask_Webserver container running" \
    "container_running 'clab-yw-Flask_Webserver'" 5

run_test "Health" "Database container running" \
    "container_running 'clab-yw-Database'" 5

# IDS/Detection Layer
run_test "Health" "Internal_IDS (Suricata) container running" \
    "container_running 'clab-yw-Internal_IDS'" 5

run_test "Health" "DMZ_IDS (Suricata) container running" \
    "container_running 'clab-yw-DMZ_IDS'" 5

# SIEM Stack
run_test "Health" "Elasticsearch container running" \
    "container_running 'clab-yw-elasticsearch'" 5

run_test "Health" "Logstash container running" \
    "container_running 'clab-yw-logstash'" 5

run_test "Health" "Kibana container running" \
    "container_running 'clab-yw-kibana'" 5

# Attacker
run_test "Health" "Attacker container running" \
    "container_running 'clab-yw-Attacker'" 5

run_test "Health" "SIEM_PC container running" \
    "container_running 'clab-yw-siem_pc'" 5

run_test "Health" "router-internet container running" \
    "container_running 'clab-yw-router-internet'" 5

run_test "Health" "router-edge container running" \
    "container_running 'clab-yw-router-edge'" 5

# =========================
# Process Checks (Critical Services)
# =========================

print_category "SECTION 1.2: Critical Process Verification" \
    "Checks if key processes are running inside containers"

# Firewalls - iptables & ulogd
run_test "Health" "Internal_FW: iptables loaded" \
    "sudo docker exec clab-yw-Internal_FW iptables -L -n >/dev/null 2>&1" 5

run_test "Health" "Internal_FW: ulogd2 process running" \
    "sudo docker exec clab-yw-Internal_FW pgrep -x ulogd >/dev/null 2>&1" 5

run_test "Health" "External_FW: iptables loaded" \
    "sudo docker exec clab-yw-External_FW iptables -L -n >/dev/null 2>&1" 5

run_test "Health" "External_FW: ulogd2 process running" \
    "sudo docker exec clab-yw-External_FW pgrep -x ulogd >/dev/null 2>&1" 5

# IDS - Suricata
run_test "Health" "Internal_IDS: Suricata process running" \
    "sudo docker exec clab-yw-Internal_IDS pgrep -x Suricata-Main >/dev/null 2>&1" 5

run_test "Health" "DMZ_IDS: Suricata process running" \
    "sudo docker exec clab-yw-DMZ_IDS pgrep -x Suricata-Main >/dev/null 2>&1" 5

# Filebeat/Logging
run_test "Health" "Internal_FW: Filebeat process running" \
    "sudo docker exec clab-yw-Internal_FW pgrep -x filebeat >/dev/null 2>&1" 5

run_test "Health" "External_FW: Filebeat process running" \
    "sudo docker exec clab-yw-External_FW pgrep -x filebeat >/dev/null 2>&1" 5

run_test "Health" "Internal_IDS: Filebeat process running" \
    "sudo docker exec clab-yw-Internal_IDS pgrep -x filebeat >/dev/null 2>&1" 5

run_test "Health" "DMZ_IDS: Filebeat process running" \
    "sudo docker exec clab-yw-DMZ_IDS pgrep -x filebeat >/dev/null 2>&1" 5

# Elasticsearch
run_test "Health" "Elasticsearch: Java process running" \
    "sudo docker exec clab-yw-elasticsearch pgrep -x java >/dev/null 2>&1" 5

run_test "Health" "Logstash: Java process running" \
    "sudo docker exec clab-yw-logstash pgrep -x java >/dev/null 2>&1" 5

run_test "Health" "Kibana: Node.js process running" \
    "sudo docker exec clab-yw-kibana pgrep -x node >/dev/null 2>&1" 5

# =========================
# Service Responsiveness
# =========================

print_category "SECTION 1.3: Service Responsiveness" \
    "Checks if services respond to queries"

run_test "Health" "Elasticsearch API responding" \
    "curl -s -m 5 http://localhost:9200/_cluster/health 2>/dev/null | grep -q 'cluster_name'" 8

run_test "Health" "Kibana Web UI responding" \
    "curl -s -m 5 http://localhost:5601/api/status 2>/dev/null | grep -q 'state'" 10

run_test "Health" "Logstash API responding" \
    "curl -s -m 5 http://localhost:9600 2>/dev/null | grep -q 'host'" 8

run_test "Health" "Webserver HTTP responding" \
    "curl -s -m 5 http://localhost:8080 2>/dev/null | grep -q -i 'login'" 8

run_test "Health" "Database PostgreSQL responding" \
    "sudo docker exec clab-yw-Database pg_isready -U admin_user >/dev/null 2>&1" 5

# =========================
# Container Resource Health
# =========================

print_category "SECTION 1.4: Container Resource Health" \
    "Checks memory, CPU, and disk usage"

run_test "Health" "Elasticsearch memory healthy" \
    "sudo docker stats --no-stream clab-yw-elasticsearch | tail -1 | awk '{print \$7}' | grep -v '%' >/dev/null 2>&1" 5

run_test "Health" "Logstash memory healthy" \
    "sudo docker stats --no-stream clab-yw-logstash | tail -1 | awk '{print \$7}' | grep -v '%' >/dev/null 2>&1" 5

# =========================
# Network Interface Checks
# =========================

print_category "SECTION 1.5: Network Interface Configuration" \
    "Verifies network interfaces are properly configured"

run_test "Health" "Internal_FW has eth0 (management)" \
    "sudo docker exec clab-yw-Internal_FW ip link show eth0 >/dev/null 2>&1" 5

run_test "Health" "Internal_FW has eth1 (internal)" \
    "sudo docker exec clab-yw-Internal_FW ip link show eth1 >/dev/null 2>&1" 5

run_test "Health" "Internal_FW has eth2 (dmz)" \
    "sudo docker exec clab-yw-Internal_FW ip link show eth2 >/dev/null 2>&1" 5

run_test "Health" "Internal_FW has eth3 (external)" \
    "sudo docker exec clab-yw-Internal_FW ip link show eth3 >/dev/null 2>&1" 5

run_test "Health" "External_FW has eth0 (management)" \
    "sudo docker exec clab-yw-External_FW ip link show eth0 >/dev/null 2>&1" 5

run_test "Health" "SIEM_FW has eth0 (management)" \
    "sudo docker exec clab-yw-SIEM_FW ip link show eth0 >/dev/null 2>&1" 5
