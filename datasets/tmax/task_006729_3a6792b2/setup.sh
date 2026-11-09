#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gawk
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/raw_data_utf8.txt
2023-10-01|20.0
2023-10-01|22.0
2023-10-02|21.0
2023-10-02|21.0
2023-10-04|25.0
2023-10-05|24.0
2023-10-05|23.0
2023-10-07|19.0
EOF

    iconv -f UTF-8 -t UTF-16LE /tmp/raw_data_utf8.txt > /home/user/raw_sensor.txt
    rm /tmp/raw_data_utf8.txt

    chmod -R 777 /home/user
