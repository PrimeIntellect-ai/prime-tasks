#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip cargo rustc
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/sensor_data.txt
sensor_A|5|48600
sensor_B|5|48700
sensor_C|5|48647
sensor_A|10|23600
sensor_B|10|23700
sensor_C|10|23671
sensor_A|20|5680
sensor_B|20|5710
sensor_C|20|5716
EOF

    chmod -R 777 /home/user
