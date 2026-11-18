#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip zip tar gzip libc-bin
    pip3 install pytest

    mkdir -p /home/user/research_data
    cd /home/user/research_data

    cat << 'EOF' > config.ini
[Tokyo_Station]
filename = tokyo.log
encoding = shift_jis

[Moscow_Station]
filename = moscow.log
encoding = koi8-r

[Berlin_Station]
filename = berlin.log
encoding = iso-8859-1
EOF

    # Create log files with specific encodings
    # Tokyo (Shift_JIS)
    cat << 'EOF' | iconv -f UTF-8 -t SHIFT_JIS > tokyo.log
===RECORD START===
STATION: Tokyo_Station
TIMESTAMP: 2021-10-01T10:00:00Z
STATUS: VALID
NOTES: 正常に動作しています
===RECORD END===
Garbage data
===RECORD START===
STATION: Tokyo_Station
TIMESTAMP: 2021-10-01T11:00:00Z
STATUS: MAINTENANCE
NOTES: メンテナンス中
===RECORD END===
EOF

    # Moscow (KOI8-R)
    cat << 'EOF' | iconv -f UTF-8 -t KOI8-R > moscow.log
===RECORD START===
STATION: Moscow_Station
TIMESTAMP: 2021-10-01T10:00:00Z
STATUS: VALID
NOTES: Система работает нормально
===RECORD END===
EOF

    # Berlin (ISO-8859-1)
    cat << 'EOF' | iconv -f UTF-8 -t ISO-8859-1 > berlin.log
===RECORD START===
STATION: Berlin_Station
TIMESTAMP: 2021-10-01T10:00:00Z
STATUS: INVALID
NOTES: Systemfehler
===RECORD END===
===RECORD START===
STATION: Berlin_Station
TIMESTAMP: 2021-10-01T11:00:00Z
STATUS: VALID
NOTES: Alles in Ordnung
===RECORD END===
EOF

    tar -czf raw_logs.tar.gz tokyo.log moscow.log berlin.log
    rm tokyo.log moscow.log berlin.log

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
