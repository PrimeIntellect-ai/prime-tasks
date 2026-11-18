#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/raw_sensor_logs.txt
1620000000,SENS-ABC-1234,22.5,200
1620000010,SENS-ABC-1234,-,200
1620000020,SENS-ABC-1234,23.0,999
1620000030,BAD-ID-123,24.0,200
1620000040,SENS-XYZ-9876,-,500
1620000050,SENS-XYZ-9876,25.1,404
1620000060,SENS-DEF-0000,-,600
1620000070,SENS-QWE-5555,-,200
EOF

    chmod -R 777 /home/user
