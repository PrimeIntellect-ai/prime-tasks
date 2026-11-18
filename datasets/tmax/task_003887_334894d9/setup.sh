#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc libc6-dev
    pip3 install pytest

    mkdir -p /home/user
    cat << 'EOF' > /home/user/citations.csv
101,102,2020
102,103,2020
103,104,2021
104,105,2021
108,103,2020
109,103,2020
110,105,2021
111,105,2022
112,111,2022
113,111,2022
114,101,2019
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
