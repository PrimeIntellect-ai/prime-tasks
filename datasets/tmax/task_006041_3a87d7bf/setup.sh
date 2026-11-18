#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc libc6-dev make
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/input.csv
ts,sensor_id,reading
10, reactor_temp ,200.0
10,reactor_temp,205.0
12,Reactor_Temp,210.0
15,reactor_temp,-50.0
18,reactor_temp,225.0
22,reactor_temp,235.0
30,reactor_temp,255.0
40,reactor_temp,400.0
50,other_sensor,410.0
50,reactor_temp,410.0
EOF

    chmod -R 777 /home/user
