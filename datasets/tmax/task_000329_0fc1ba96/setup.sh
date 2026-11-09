#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip build-essential
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/measurements.csv
machine_id,measurement,flag
1,10.5,VALID
2,20.1,VALID
,15.0,VALID
1,11.2,VALID
1,9.8,INVALID
2,22.4,VALID
1,10.8,VALID
2,19.5,VALID
1,11.5,VALID
2,21.0,VALID
,12.0,VALID
1,10.1,VALID
EOF

    chmod -R 777 /home/user
