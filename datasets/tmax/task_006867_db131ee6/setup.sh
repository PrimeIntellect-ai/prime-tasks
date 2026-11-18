#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip libc-bin
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/logs

    # 1. en_log.csv (UTF-8)
    cat << 'EOF' > /home/user/logs/en_log.csv
2023-10-01T10:00:00Z,20.0,System OK
2023-10-01T10:04:00Z,60.0,High Temp Warning
2023-10-01T10:00:00Z,20.0,System OK
EOF

    # 2. jp_log.csv (UTF-16LE)
    cat << 'EOF' > /tmp/jp_temp.csv
2023-10-01T10:01:00Z,22.0,正常
2023-10-01T10:05:00Z,80.0,重大な警告
EOF
    iconv -f UTF-8 -t UTF-16LE /tmp/jp_temp.csv > /home/user/logs/jp_log.csv

    # 3. de_log.csv (ISO-8859-1)
    cat << 'EOF' > /tmp/de_temp.csv
2023-10-01T10:02:00Z,21.0,Normalbetrieb
2023-10-01T10:03:00Z,25.0,Achtung
2023-10-01T10:02:00Z,21.0,Normalbetrieb
EOF
    iconv -f UTF-8 -t ISO-8859-1 /tmp/de_temp.csv > /home/user/logs/de_log.csv

    chmod -R 777 /home/user
