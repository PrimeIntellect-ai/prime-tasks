#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc build-essential curl
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/data /home/user/pipeline /home/user/public_html

    cat << 'EOF' > /home/user/data/sensor_readings.csv
timestamp,sensor_id,value,notes
2023-01-01T00:00:00Z,S-100,10.0,"All good"
2023-01-01T00:01:00Z,S-200,99.9,"Ignore this"
2023-01-01T00:02:00Z,S-100,12.0,"Normal"
2023-01-01T00:03:00Z,S-100,15.0,"Multiline
note here"
2023-01-01T00:04:00Z,S-100,14.0,"Note"
2023-01-01T00:05:00Z,S-100,16.0,"Another
newline
test"
2023-01-01T00:06:00Z,S-100,15.0,"Short"
2023-01-01T00:07:00Z,S-100,18.0,"End"
EOF

    chown -R user:user /home/user/data /home/user/pipeline /home/user/public_html
    chmod -R 777 /home/user
