#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc libc6-dev
    pip3 install pytest

    mkdir -p /home/user/raw_configs

    cat << 'EOF' > /home/user/raw_configs/1_web.conf
# Main web config
Port = 8080   
  host_name= web-server-01

db_host = database.local
db_port = 5432
EOF

    cat << 'EOF' > /home/user/raw_configs/2_worker.conf
# Worker config
  WORKER_THREADS = 4
db_host=database.local
DB_PORT =   5432
  queue_url = redis://localhost:6379 
EOF

    cat << 'EOF' > /home/user/raw_configs/3_cache.conf
host_name = cache-server-01
queue_url = redis://localhost:6379
# end of file
EOF

    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user
    chmod -R 777 /home/user
