#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gawk sed grep coreutils bc
    pip3 install pytest

    mkdir -p /home/user
    cat << 'EOF' > /home/user/raw_sensors.log
2023-11-01 [INFO] pos: <12.0, 5.0, 0.0> - signal stable
2023-11-02 [WARN] pos: ( 3.0, 4.0, 12.0 ) - signal weak
2023-11-03 [DEBUG] position=[0.0, 8.0, 6.0]
2023-11-04 [INFO] coords=2.0, -2.0, 1.0
2023-11-05 [ERROR] loc:< -6.0 , 0.0 , 8.0 >
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
