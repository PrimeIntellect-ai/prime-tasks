#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gawk coreutils sed grep diffutils
    pip3 install pytest

    mkdir -p /home/user
    cat << 'EOF' > /home/user/etl_dump.csv
timestamp,sensor_value,event_description
1001,45.0,System START!!
1002,46.2,All Good.
1003,MISSING,Running smoothly...
1001,45.0,System START!!
1002,46.2,All Good.
1004,47.1,Temp normal
1005,95.5,WARNING: OVERHEAT!!!
1006,MISSING,Cooling down
1007,48.0,Recovered.
1008,49.0,Status: OK
1009,48.5,Status: OK
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
