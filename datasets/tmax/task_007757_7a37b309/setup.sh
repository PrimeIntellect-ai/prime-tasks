#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/telemetry_input

    cat << 'EOF' > /home/user/telemetry_input/region1.csv
timestamp,sensor_id,metric_type,value,unit
2023-10-01T10:00:00Z,S1,temp,68.0,F
2023-10-01T11:00:00Z,S1,temp,22.0,C
2023-10-01T10:00:00Z,S2,humidity,45.0,%
EOF

    cat << 'EOF' > /home/user/telemetry_input/region2.csv
timestamp,sensor_id,metric_type,value,unit
2023-10-01T12:00:00Z,S2,humidity,110.0,%
2023-10-01T12:00:00Z,S1,temp,150.0,F
2023-10-01T12:00:00Z,S3,pressure,1013.0,hPa
EOF

    cat << 'EOF' > /home/user/telemetry_input/region3.csv
timestamp,sensor_id,metric_type,value,unit
2023-10-01T13:00:00Z,S3,pressure,1015.0,hPa
2023-10-01T13:00:00Z,S2,humidity,55.0,%
2023-10-01T13:00:00Z,S1,temp,24.0,C
2023-10-01T13:00:00Z,S4,temp,invalid,C
EOF

    chmod -R 777 /home/user
