#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc libc6-dev coreutils findutils gawk
    pip3 install pytest

    mkdir -p /home/user/sensor_data

    cat << 'EOF' > /home/user/sensor_data/floor_1.csv
timestamp,T1,H1
1000,22.5,50.1
1001,22.6,50.2
1002,22.7,50.3
EOF

    cat << 'EOF' > /home/user/sensor_data/floor_2.csv
timestamp,T2,H2,P1
1000,23.1,49.8,101.2
1001,23.0,49.9,101.3
1003,22.9,50.0,101.4
EOF

    cat << 'EOF' > /home/user/metadata.csv
H1,humidity
H2,humidity
P1,pressure
T1,temperature
T2,temperature
EOF

    cat << 'EOF' > /home/user/.expected_output.csv
1000,H1,humidity,50.1
1000,H2,humidity,49.8
1000,P1,pressure,101.2
1000,T1,temperature,22.5
1000,T2,temperature,23.1
1001,H1,humidity,50.2
1001,H2,humidity,49.9
1001,P1,pressure,101.3
1001,T1,temperature,22.6
1001,T2,temperature,23.0
1002,H1,humidity,50.3
1002,T1,temperature,22.7
1003,H2,humidity,50.0
1003,P1,pressure,101.4
1003,T2,temperature,22.9
EOF

    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user/sensor_data /home/user/metadata.csv /home/user/.expected_output.csv
    chmod -R 777 /home/user
