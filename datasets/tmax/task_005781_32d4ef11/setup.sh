#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip cron gawk
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user

    cat << 'EOF' > /tmp/raw_data.utf8.log
2023-10-24T14:10:00Z | srv-1 | 500 | Système défaillant
2023-10-24T14:20:00Z | srv-2 | 500 | Connexion échouée
2023-10-24T14:30:00Z | srv-1 | 500 | Timeout réseau
2023-10-24T14:40:00Z | srv-3 | 200 | OK
2023-10-24T15:10:00Z | srv-1 | 500 | Erreur interne
2023-10-24T15:20:00Z | srv-2 | 500 | Erreur interne
2023-10-24T16:05:00Z | srv-1 | 500 | Crash
2023-10-24T16:15:00Z | srv-2 | 500 | Crash
2023-10-24T16:25:00Z | srv-3 | 500 | Crash
2023-10-24T16:35:00Z | srv-1 | 500 | Crash
EOF

    iconv -f UTF-8 -t ISO-8859-1 /tmp/raw_data.utf8.log > /home/user/raw_data.log
    rm /tmp/raw_data.utf8.log

    chown -R user:user /home/user
    chmod -R 777 /home/user
