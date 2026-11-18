#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gawk
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/dirty_temperatures.txt
timestamp|temperature_celsius
2023-10-01T10:00:00Z|10.0
2023-10-01T11:00:00Z|15.0
2023-10-01T12:00:00Z|
2023-10-01T13:00:00Z|999.9
bad_timestamp_14|20.0
2023-10-01T14:00:00Z|20.0
2023-10-01T15:00:00Z|30.0
2023-10-01T16:00:00Z|
2023-10-01T17:00:00Z|-50.0
2023-10-01T18:00:00Z|
EOF
    chmod 644 /home/user/dirty_temperatures.txt

    chmod -R 777 /home/user
