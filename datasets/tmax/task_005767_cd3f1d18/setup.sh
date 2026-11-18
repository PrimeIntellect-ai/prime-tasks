#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/raw_telemetry.txt
A1|1700000000|10.0
A1|1700000060|-25.0
A1|1700000120|12.5
A1|1700000240|13.0
B2|1700000060|22.0
B2|1700000120|22.5
B2|1700000180|80.0
B2|1700000300|21.0
C3|1700000000|5.0
EOF

    chmod -R 777 /home/user
