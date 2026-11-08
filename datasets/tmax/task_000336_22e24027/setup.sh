#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest pandas numpy

    mkdir -p /home/user/data/

    cat << 'EOF' > /home/user/data/run_1.csv
ts,sensor_a,sensor_b
1696161600.1,10.5,8.2
1696161601.0,11.0,8.5
1696161605.9,12.5,
1696161606.1,12.6,9.1
1696161610.0,,10.0
EOF

    cat << 'EOF' > /home/user/data/retry_1.json
{"datetime": "2023-10-01T14:00:00.300000+02:00", "val_a": 10.7, "val_b": 8.0}
{"datetime": "2023-10-01T14:00:05.800000+02:00", "val_a": 12.1, "val_b": 9.0}
{"datetime": "2023-10-01T14:00:10.200000+02:00", "val_a": 14.0, "val_b": 10.2}
{"datetime": "2023-10-01T14:00:15.000000+02:00", "val_a": 15.0, "val_b": 11.5}
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
