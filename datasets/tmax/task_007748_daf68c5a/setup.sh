#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest pandas

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/input_data
    mkdir -p /home/user/output_data

    cat << 'EOF' > /home/user/input_data/sensor_a.csv
timestamp,sensor_id,temperature,humidity
1633046400,A,20.0,40.0
1633046460,A,,41.0
1633046520,A,22.0,42.0
1633046400,A,20.0,40.0
1633046580,A,23.0,43.0
EOF

    cat << 'EOF' > /home/user/input_data/sensor_b.csv
timestamp,sensor_id,temperature,humidity
2021-10-01T00:00:00Z,B,15.0,50.0
2021-10-01T00:01:00Z,B,,51.0
2021-10-01T00:02:00Z,B,17.0,52.0
2021-10-01T00:00:00Z,B,15.0,50.0
EOF

    chmod -R 777 /home/user
