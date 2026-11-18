#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip jq gawk
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user
    cat << 'EOF' > /home/user/telemetry.csv
timestamp,sensor_id,ip_address,payload,notes
2023-10-01T10:00:00Z,S1,192.168.1.101,"{""temp"": 22.1, ""status"": ""ok""}","All good"
2023-10-01T10:01:00Z,S2,10.0.0.5,"{""temp"": 24.5, ""status"": ""warn""}","Sensor bumped
need to check calibration"
2023-10-01T10:02:00Z,S1,192.168.1.101,"{""status"": ""error""}","No temp reading"
2023-10-01T10:03:00Z,S3,172.16.0.4,"{""temp"": 21.0}",""
2023-10-01T10:04:00Z,S4,8.8.8.8,"{""temp"": -5.4, ""battery"": 80}","Cold weather
warning
issued"
EOF

    chmod -R 777 /home/user
