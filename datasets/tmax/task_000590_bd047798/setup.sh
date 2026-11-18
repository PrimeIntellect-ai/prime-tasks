#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip jq gawk coreutils
    pip3 install pytest

    mkdir -p /home/user
    cat << 'EOF' > /home/user/raw_sensor_data.csv
timestamp,sensor_id,value,notes
1600000000,S1,15.5,"Normal reading"
1600000005,S1,15.5,"Normal reading duplicate"
1600000010,S1,45.0,"Spike
detected"
1600000010,S1,45.0,"Duplicate spike"
1600000015,S2,10.0,"S2 start"
1600000020,S1,16.0,"Back to
normal"
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
