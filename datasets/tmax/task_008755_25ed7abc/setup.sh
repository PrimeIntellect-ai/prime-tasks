#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip zip tar
    pip3 install pytest

    mkdir -p /home/user/logs/tmp_setup/server_A
    mkdir -p /home/user/logs/tmp_setup/server_B
    mkdir -p /home/user/logs/tmp_setup/server_C

    # Server A Data
    cat << 'EOF' > /home/user/logs/tmp_setup/server_A/data1.json
[
  {"file_path": "/var/data/db.sqlite", "size_bytes": 500000000},
  {"file_path": "/var/log/syslog", "size_bytes": 15000}
]
EOF
    cat << 'EOF' > /home/user/logs/tmp_setup/server_A/data2.csv
file_path,size_bytes
/var/log/nginx/access.log,120000000
/home/user/videos/cat.mp4,800000000
EOF

    # Server B Data
    cat << 'EOF' > /home/user/logs/tmp_setup/server_B/logs.csv
file_path,size_bytes
/backup/db_dump.tar.gz,1500000000
/opt/app/cache.bin,350000000
EOF
    cat << 'EOF' > /home/user/logs/tmp_setup/server_B/extra.json
[
  {"file_path": "/usr/lib/libhuge.so", "size_bytes": 420000000}
]
EOF

    # Server C Data
    cat << 'EOF' > /home/user/logs/tmp_setup/server_C/archive.csv
file_path,size_bytes
/home/user/docs.zip,600000000
/tmp/garbage.bin,350000000
EOF

    # Zip them up
    cd /home/user/logs/tmp_setup/server_A && zip -q A_logs.zip data1.json data2.csv && rm data1.json data2.csv
    cd /home/user/logs/tmp_setup/server_B && zip -q B_logs.zip logs.csv extra.json && rm logs.csv extra.json
    cd /home/user/logs/tmp_setup/server_C && zip -q C_logs.zip archive.csv && rm archive.csv

    # Tar them up
    cd /home/user/logs/tmp_setup && tar -czf /home/user/logs/server_usage.tar.gz server_A server_B server_C
    rm -rf /home/user/logs/tmp_setup

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
