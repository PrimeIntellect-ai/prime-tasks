#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gzip cargo
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/raw_logs/cluster_A /home/user/raw_logs/cluster_B
    mkdir -p /home/user/organized_logs

    create_log() {
        local path=$1
        local app_id=$2
        local timestamp=$3
        printf '{"app_id": "%s", "timestamp": %d}\nLog entry 1\nLog entry 2\n' "$app_id" "$timestamp" | gzip > "$path"
    }

    create_log "/home/user/raw_logs/cluster_A/node1_sys.gz" "auth_service" 1690000010
    create_log "/home/user/raw_logs/cluster_A/node2_sys.gz" "auth_service" 1690000050
    create_log "/home/user/raw_logs/cluster_A/db_dump.gz" "db_service" 1680000000
    create_log "/home/user/raw_logs/cluster_B/node1_sys.gz" "auth_service" 1690000020
    create_log "/home/user/raw_logs/cluster_B/db_dump.gz" "db_service" 1680000100
    create_log "/home/user/raw_logs/cluster_B/metrics.gz" "metrics_service" 1690000000

    chown -R user:user /home/user/raw_logs /home/user/organized_logs
    chmod -R 777 /home/user
