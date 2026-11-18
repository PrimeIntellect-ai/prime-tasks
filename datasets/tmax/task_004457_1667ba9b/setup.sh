#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/raw_configs

    # Use variables to avoid literal double curly braces in the def file
    LBR="{"
    RBR="}"

    cat << EOF > /home/user/report_template.txt
## Role: ${LBR}${LBR}ROLE${RBR}${RBR}
Latest Timestamp: ${LBR}${LBR}TIMESTAMP${RBR}${RBR}
Server ID: ${LBR}${LBR}SERVER_ID${RBR}${RBR}
Configuration:
${LBR}${LBR}CONFIG_PAIRS${RBR}${RBR}

EOF

    cat << 'EOF' > /home/user/raw_configs/server_1_db_100.conf
# Old DB config
Port = 5432
MaxConnections = 100
EOF

    cat << 'EOF' > /home/user/raw_configs/server_2_db_200.conf
# New DB config
  port= 5432  
maxConnections  =  200
timeout = 30
EOF

    cat << 'EOF' > /home/user/raw_configs/server_3_web_150.conf
# Web config
Workers = 4
PORT = 8080 
EOF

    cat << 'EOF' > /home/user/raw_configs/server_4_web_120.conf
# Old Web config
Workers = 2
PORT = 80
EOF

    cat << 'EOF' > /home/user/raw_configs/server_5_cache_300.conf
# Cache config
  MemLimit = 4G
Eviction = LRU  
EOF

    chmod -R 777 /home/user
