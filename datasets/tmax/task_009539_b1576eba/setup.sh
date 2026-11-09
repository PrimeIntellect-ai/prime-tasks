#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest pandas scikit-learn

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/data/raw
    cat << 'EOF' > /home/user/data/raw/messy_sensors.csv
sensor_id,temperature,humidity,soil_moisture,yield_class
GH-001,22.5,45.0,60.0,1
GH-002,15.0,80.0,50.0,0
GH-003,35.5,30.0,10.0,2
XX-004,25.0,50.0,60.0,1
GH-005,error,50.0,60.0,1
GH-006,20.0,95.0,60.0,1
GH-007,20.0,50.0,150.0,1
GH-008,20.0,50.0,60.0,3
GH-009,24.0,55.0,65.0,1
GH-010,21.0,40.0,55.0,1
GH-011,28.0,35.0,45.0,2
GH-012,18.0,75.0,55.0,0
GH-013,12.0,85.0,65.0,0
GH-014,38.0,25.0,15.0,2
GH-015,26.0,48.0,58.0,1
GH-016,19.0,78.0,52.0,0
GH-017,34.0,32.0,20.0,2
GH-018,23.5,47.0,62.0,1
GH-019,29.0,38.0,40.0,2
GH-020,16.0,82.0,48.0,0
GH-021,27.0,42.0,50.0,1
GH-022,36.0,28.0,18.0,2
GH-023,14.0,88.0,58.0,0
GH-024,25.5,46.0,61.0,1
GH-025,32.0,34.0,25.0,2
EOF

    chmod -R 777 /home/user
