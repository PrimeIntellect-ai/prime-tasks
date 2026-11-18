#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip jq
    pip3 install pytest pandas

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/sensor_a.csv
ts_sec,temp
1672531200,20.0
1672531260,21.0
1672531260,21.5
1672531380,22.0
1672531440,23.0
1672531500,22.5
EOF

    cat << 'EOF' > /home/user/sensor_b.json
[
  {"time": 1672531200, "t": 18.0},
  {"time": 1672531320, "t": 19.0},
  {"time": 1672531380, "t": 19.5},
  {"time": 1672531440, "t": 20.0},
  {"time": 1672531500, "t": 20.0}
]
EOF

    chmod -R 777 /home/user
