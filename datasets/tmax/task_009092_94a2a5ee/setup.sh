#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/raw_events.csv
1700000000,101,Alice Smith,alice@example.com,click
1700000050,102,Bob Jones,bob@example.com,view
1700000000,101,Alice Smith,alice@example.com,click
1700003500,103,Charlie Brown,charlie@example.com,purchase
1700003600,101,Alice Smith,alice@example.com,view
1700003600,101,Alice Smith,alice@example.com,view
1700007200,104,Diana Prince,diana@example.com,click
1700000050,102,Bob Jones,bob@example.com,view
EOF

    chmod -R 777 /home/user
