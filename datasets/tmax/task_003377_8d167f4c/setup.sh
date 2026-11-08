#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/data
    mkdir -p /home/user/output

    cat << 'EOF' > /home/user/data/server_meta.csv
ServerID,IP_Address,Datacenter
Srv-Alpha,10.0.0.1,US-East
Srv-Beta,10.0.0.2,US-East
Srv-Gamma,10.0.1.5,US-West
Srv-Delta,10.0.2.10,EU-Central
EOF

    cat << 'EOF' | iconv -f UTF-8 -t UTF-16LE > /home/user/data/server_configs.log
[2023-11-02 08:30:00] CONFIG_UPDATE: ServerID:Srv-Alpha upgraded package 'nginx' to version:v1.18.0
[2023-11-02 08:45:12] CONFIG_UPDATE: ServerID:Srv-Beta upgraded package 'postgresql' to version:v13.4
[MISSING] CONFIG_UPDATE: ServerID:Srv-Gamma upgraded package 'openssl' to version:v1.1.1k
[2023-11-02 08:45:12] CONFIG_UPDATE:  ServerID:Srv-Beta upgraded package 'postgresql' to version:v13.4  
[2023-11-02 09:10:00] CONFIG_UPDATE: ServerID:Srv-Alpha upgraded package 'python3' to version:v3.9.7
[MISSING] CONFIG_UPDATE: ServerID:Srv-Gamma upgraded package 'openssl' to version:v1.1.1k
[2023-11-02 09:15:30] CONFIG_UPDATE: ServerID:Srv-Unknown upgraded package 'docker' to version:v20.10.8
[2023-11-02 09:20:00] CONFIG_UPDATE: ServerID:Srv-Delta upgraded package 'redis' to version:v6.2.5
[MISSING] CONFIG_UPDATE: ServerID:Srv-Alpha upgraded package 'htop' to version:v3.0.5
EOF

    chmod -R 777 /home/user
