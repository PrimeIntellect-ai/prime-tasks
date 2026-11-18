#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/sensor_data.log
2023-10-12 10:00:01 INFO [SensorA] detected object at {x: 12.0, y: -5.0, z: 2.5} with confidence 0.98
DEBUG metric update {x: 3.0, y: 4.0, z: 0.0} status OK
WARN target lost near {x: 12.0, y: -5.0, z: 2.5} - retrying
INFO drone base {x: 0.0, y: 0.0, z: 0.0} initialized
ERROR calibration failed at {x: -2.0, y: 1.5, z: 10}
2023-10-12 10:05:01 INFO [SensorA] detected object at {x: 12.0, y: -5.0, z: 2.5} with confidence 0.99
TRACE random coordinates: {x: 0.5, y: -0.5, z: 0.5}
EOF

    chmod -R 777 /home/user
