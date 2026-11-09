#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip jq gawk coreutils
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/backup_logs/

    cat << 'EOF' > /home/user/backup_logs/log1.json
{"job_id": "j001", "cluster": "db-cluster-omega", "type": "full", "status": "success"}
EOF

    cat << 'EOF' > /home/user/backup_logs/log2.json
{"job_id": "j002", "cluster": "db-cluster-omega", "type": "full", "parent_job_id": null, "status": "success", "size_bytes": 10000, "timestamp": 1600000000}
EOF

    cat << 'EOF' > /home/user/backup_logs/log3.json
{"job_id": "j003", "cluster": "db-cluster-omega", "type": "incremental", "parent_job_id": "j002", "status": "success", "size_bytes": 500, "timestamp": 1600001000}
EOF

    cat << 'EOF' > /home/user/backup_logs/log4.json
{"job_id": "j004", "cluster": "db-cluster-omega", "type": "incremental", "parent_job_id": "j003", "status": "success", "size_bytes": 800, "timestamp": 1600002000}
EOF

    cat << 'EOF' > /home/user/backup_logs/log5.json
{"job_id": "j005", "cluster": "db-cluster-omega", "type": "incremental", "parent_job_id": "j003", "status": "failed", "size_bytes": 900, "timestamp": 1600002500}
EOF

    cat << 'EOF' > /home/user/backup_logs/log6.json
{"job_id": "j006", "cluster": "db-cluster-omega", "type": "incremental", "parent_job_id": "j003", "status": "success", "size_bytes": 200, "timestamp": 1600003000}
EOF

    cat << 'EOF' > /home/user/backup_logs/log7.json
{"job_id": "j007", "cluster": "db-cluster-omega", "type": "incremental", "parent_job_id": "j006", "status": "success", "size_bytes": 300, "timestamp": 1600004000}
EOF

    cat << 'EOF' > /home/user/backup_logs/log8.json
{"job_id": "j008", "cluster": "db-cluster-alpha", "type": "full", "parent_job_id": null, "status": "success", "size_bytes": 20000, "timestamp": 1600000000}
EOF

    chown -R user:user /home/user/backup_logs/
    chmod -R 777 /home/user
