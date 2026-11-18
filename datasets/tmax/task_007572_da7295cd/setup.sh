#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++ wget make
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/raw_sensors.csv
timestamp,sensor_id,raw_value
1620000000,S1,10.5
1620000001,S2,22.1
1620000002,S1,10.6
1620000003,S3,5.0
1620000004,S2,22.0
EOF

    cat << 'EOF' > /home/user/calibrations.json
{
  "S1": {"scale": 1.2, "offset": -0.5},
  "S2": {"scale": 0.98, "offset": 0.1}
}
EOF

    chmod -R 777 /home/user
