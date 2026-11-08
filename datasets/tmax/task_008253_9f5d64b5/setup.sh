#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gawk coreutils
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/sensor_data/

    cat << 'EOF' > /home/user/sensor_data/sensor_A.csv
timestamp,sensor_id,temperature,humidity
2023-10-01T00:00:00Z,SENS-A,22.1,45
2023-10-01T00:10:00Z,SENS-A,22.2,46
2023-10-01T00:20:00Z,SENS-A,22.3,45
2023-10-01T00:30:00Z,SENS-A,22.4,44
2023-10-01T00:40:00Z,SENS-A,22.5,43
2023-10-01T00:50:00Z,SENS-A,22.4,43
2023-10-01T01:00:00Z,SENS-A,22.3,44
2023-10-01T01:10:00Z,SENS-A,22.2,45
2023-10-01T01:20:00Z,SENS-A,22.1,46
2023-10-01T01:30:00Z,SENS-A,22.0,47
2023-10-01T01:40:00Z,SENS-A,21.9,48
2023-10-01T01:50:00Z,SENS-A,21.8,49
2023-10-01T02:00:00Z,SENS-A,21.7,50
2023-10-01T02:10:00Z,SENS-A,21.6,51
2023-10-01T02:20:00Z,SENS-A,21.5,52
EOF

    cat << 'EOF' > /home/user/sensor_data/sensor_B.csv
timestamp,sensor_id,temperature,humidity
2023-10-01T00:05:00Z,SENS-B,18.1,65
2023-10-01T00:15:00Z,SENS-B,18.2,66
2023-10-01T00:25:00Z,SENS-B,18.3,65
2023-10-01T00:35:00Z,SENS-B,18.4,64
2023-10-01T00:45:00Z,SENS-B,18.5,63
2023-10-01T00:55:00Z,SENS-B,18.4,63
2023-10-01T01:05:00Z,SENS-B,18.3,64
2023-10-01T01:15:00Z,SENS-B,18.2,65
2023-10-01T01:25:00Z,SENS-B,18.1,66
2023-10-01T01:35:00Z,SENS-B,18.0,67
2023-10-01T01:45:00Z,SENS-B,17.9,68
EOF

    cp /home/user/sensor_data/sensor_A.csv /home/user/sensor_data/sensor_A_dup.csv

    cat << 'EOF' > /home/user/sensor_data/corrupt.csv
timestamp,sensor_id,temperature,humidity
2023-10-01T00:00:00Z,SENS-C,22.1,45
2023-10-01T00:10:00Z,SENS-C,22.2
2023-10-01T00:20:00Z,SENS-C,22.3,45
EOF

    chmod -R 777 /home/user
