#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest pandas numpy

    # Create directories
    mkdir -p /home/user/raw_data

    # Create sensor_A.csv
    cat << 'EOF' > /home/user/raw_data/sensor_A.csv
timestamp,temp,humidity
1600000000,20.0,50.0
1600000060,21.0,55.0
1600000120,120.0,52.0
1600000180,23.0,58.0
1600000240,24.0,
1600000300,25.0,60.0
1600000360,26.0,65.0
1600000420,-60.0,63.0
1600000480,28.0,68.0
1600000540,29.0,70.0
EOF

    # Create sensor_B.csv
    cat << 'EOF' > /home/user/raw_data/sensor_B.csv
timestamp,pressure,radiation
1600000000,1010.0,10.0
1600000060,1005.0,11.0
1600000120,1008.0,12.0
1600000180,1002.0,13.0
1600000240,1000.0,14.0
1600000300,995.0,15.0
1600000360,990.0,16.0
1600000420,992.0,17.0
1600000480,985.0,18.0
1600000540,980.0,19.0
EOF

    # Create user and set permissions
    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
