#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gawk
    pip3 install pytest pandas

    mkdir -p /home/user

    cat << 'EOF' > /home/user/raw_data.log
[TRK-001] 2023-10-01T10:00:00Z Temp:10.0C Status:OK
[TRK-001] 2023-10-01T10:15:00Z Temp:16.0C Status:OK
[TRK-001] 10/01/2023 10:06:00 Temp:99.9C Status:ERROR
[TRK-002] 10/01/2023 11:00:00 Temp:20.0C Status:OK
[TRK-002] 10/01/2023 11:03:00 Temp:-50.0C Status:FAIL
[TRK-002] 2023-10-01T11:10:00Z Temp:22.0C Status:OK
[TRK-003] 2023-10-01T12:00:00Z Temp:5.0C Status:OK
[TRK-003] 10/01/2023 12:20:00 Temp:15.0C Status:OK
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
