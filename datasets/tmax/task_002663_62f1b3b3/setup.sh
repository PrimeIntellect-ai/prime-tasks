#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gawk coreutils sed grep
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/server_A
    mkdir -p /home/user/server_B

    cat << 'EOF' > /home/user/server_A/app.log
2023-10-12T13:45:00Z [INFO] System startup
2023-10-12T14:15:00Z [ERROR] Base de données hors ligne
2023-10-12T14:17:00Z [ERROR] Base de données hors ligne
2023-10-12T14:59:00Z [WARNING] High latency detected
2023-10-12T15:05:00Z [CRITICAL] Disk full
2023-10-12T15:20:00Z [ERROR] Connexion perdue
EOF

    cat << 'EOF' > /home/user/server_B/app.log
2023-10-12T14:45:00Z [ERROR] データベースエラー
2023-10-12T14:50:00Z [ERROR] データベースエラー
2023-10-12T15:10:00Z [CRITICAL] Speicherplatz voll
2023-10-12T15:12:00Z [ERROR] データベースエラー
2023-10-12T15:15:00Z [ERROR] データベースエラー
2023-10-12T15:25:00Z [CRITICAL] Speicherplatz voll
EOF

    chmod -R 777 /home/user
