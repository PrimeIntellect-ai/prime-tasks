#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang cron
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/raw_data.csv
id,email,latitude,longitude
1,alice@example.com,40.71,-74.00
2,bob@test.org,95.00,10.00
3,charlie@domain.com,-10.50,20.00
4,david@site.net,0.00,0.00
5,eve@corp.com,abc,10
6,frank@hello.com,-45.00,-45.00
7,grace@mail.com,-91.00,0.00
8,heidi@web.com,10.00,181.00
9,ivan@tech.co,10.00,-20.50
EOF

    chmod -R 777 /home/user
