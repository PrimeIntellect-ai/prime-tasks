#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/raw_events.csv
1620000000,TX101,es,500,85.0
1620000100,TX101,es,500,90.0
1620003500,TX102,fr,200,92.0
1620004000,TX103,de,150,90.0
1620005000,TX104,it,100,94.0
1620007200,TX105,es,300,88.0
1620007300,TX106,fr,400,88.0
1620014400,TX107,de,200,75.0
1620014500,TX108,it,300,73.0
1620014500,TX108,it,300,75.0
EOF

    chmod -R 777 /home/user
