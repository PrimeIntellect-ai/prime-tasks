#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    mkdir -p /home/user/logs

    cat << 'EOF' > /home/user/logs/auth.log
[2023-10-25T14:30:15Z] INFO User logged in
[2023-10-25T14:30:18Z] ERROR Connection timeout
[2023-10-25T14:30:20Z] ERROR Request Timeout on API
[2023-10-25T14:30:25Z] INFO Data synced
EOF

    cat << 'EOF' > /home/user/logs/payment.log
1698244216500 [情報] セッション開始
1698244217000 [エラー] データベース タイムアウト
1698244222000 [エラー] ネットワーク タイムアウト
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
