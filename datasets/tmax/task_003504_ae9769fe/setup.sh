#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/raw.csv
Time,Station,Data
1,Alpha,"Temp: 20.0
Hum: 50.0"
2,Alpha,"Hum: 52.0"
3,Alpha,"Temp: 24.0
Hum: 51.0"
1,Beta,"Temp: 15.0"
2,Beta,"Temp: 16.0
Hum: 60.0"
EOF

    chmod -R 777 /home/user
