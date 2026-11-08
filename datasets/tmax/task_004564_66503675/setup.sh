#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang
    pip3 install pytest

    mkdir -p /home/user

    cat << 'EOF' > /home/user/devices.json
[
  {"device_id": "dev1", "region": "North", "active": true},
  {"device_id": "dev2", "region": "North", "active": true},
  {"device_id": "dev3", "region": "South", "active": false},
  {"device_id": "dev4", "region": "South", "active": true},
  {"device_id": "dev5", "region": "East", "active": true}
]
EOF

    cat << 'EOF' > /home/user/sensor_data.csv
1620000000,dev1,10.0,40
1620000060,dev1,,41
1620000120,dev1,16.0,42
1620000180,dev1,12.0,43
1620000000,dev2,20.0,30
1620000060,dev2,,31
1620000120,dev2,,32
1620000180,dev2,26.0,33
1620000000,dev3,50.0,20
1620000060,dev3,52.0,21
1620000000,dev4,25.0,50
1620000060,dev4,27.0,51
1620000120,dev4,29.0,52
1620000180,dev4,,53
1620000240,dev4,25.0,54
1620000000,dev5,15.0,60
1620000060,dev5,18.0,61
1620000120,dev5,,62
1620000180,dev5,24.0,63
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
