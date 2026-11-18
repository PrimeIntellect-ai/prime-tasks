#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gawk coreutils sed
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/events.txt
2023-11-01 10:00:00 | ERROR | Disk full
11/01/2023 10:00:00 | ERROR | Disk full
1698832800 | ERROR | Disk full
2023-11-01 10:05:00 | WARN | CPU high
1698833100 | WARN | CPU high
11/01/2023 10:10:00 | INFO | Service up
2023-11-01 10:10:00 | INFO | Service up
1698833400 | INFO | Service up
2023-11-02 08:30:00 | ERROR | Network timeout
1698913800 | ERROR | Network timeout
EOF

    chmod -R 777 /home/user
