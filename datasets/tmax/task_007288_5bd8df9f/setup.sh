#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gawk coreutils sed grep
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/incoming

    # Region 1: UTC timestamps, UTF-8 encoded
    cat << 'EOF' > /home/user/incoming/region1.csv
timestamp,region,cpu,mem
2023-10-01 10:00:00,R1,50.0,1024.0
2023-10-01 10:01:00,R1,-5.0,2048.0
2023-10-01 10:02:00,R1,60.0,1024.0
2023-10-01 10:03:00,R1,70.0,2048.0
EOF

    # Region 2: Unix epoch timestamps, ISO-8859-1 encoded
    cat << 'EOF' | iconv -f UTF-8 -t ISO-8859-1 > /home/user/incoming/region2.csv
timestamp,region,cpu,mem
1696154400,R2,40.0,512.0
1696154460,R2,50.0,1024.0
1696154520,R2,60.0,2048.0
EOF

    chown -R user:user /home/user/incoming
    chmod -R 777 /home/user
