#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++ build-essential
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/config_changes.csv
timestamp,user_ip,server_id,config_key,old_size_bytes,new_size_bytes
1622540000,192.168.1.50,srv-01,max_connections,100,200
1622540005,10.0.0.5,srv-02,timeout,30,60
1622540010,172.16.254.1,srv-01,memory_limit,1024,2048
1622540015,192.168.1.50,srv-03,log_level,1,2
1622540020,8.8.8.8,srv-02,cache_size,500,200
EOF

    chmod -R 777 /home/user
