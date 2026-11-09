#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++
    pip3 install pytest

    mkdir -p /home/user

    cat << 'EOF' > /home/user/sensor_a.log
[2023-10-25 14:22:01.150] INFO: Position detected at X=12.50 Y=4.20
[2023-10-25 14:22:02.500] INFO: Position detected at X=15.00 Y=5.00
[2023-10-25 14:22:03.100] INFO: Position detected at X=10.00 Y=10.00
[2023-10-25 14:22:04.900] INFO: Position detected at X=0.00 Y=0.00
EOF

    cat << 'EOF' > /home/user/sensor_b.log
[2023-10-25 14:22:01.180] TRACE: Object tracking - coord: (12.40, 4.30)
[2023-10-25 14:22:02.550] TRACE: Object tracking - coord: (12.00, 2.00)
[2023-10-25 14:22:03.250] TRACE: Object tracking - coord: (10.10, 10.10)
[2023-10-25 14:22:04.990] TRACE: Object tracking - coord: (3.00, 4.00)
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
