#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest pandas numpy scikit-learn

    mkdir -p /home/user/data

    cat << 'EOF' > /home/user/data/sensors.csv
sensor_id,location,installation_year
1,North,2015
2,South,2016
,East,2017
4,West,2018
5,Central,2019
EOF

    cat << 'EOF' > /home/user/data/readings.csv
sensor_id,timestamp,value
1,2023-01-01,10.5
2,2023-01-01,12.2
4,2023-01-01,9.8
5,2023-01-01,11.1
6,2023-01-01,15.0
EOF

    cat << 'EOF' > /home/user/data/targets.csv
sensor_id,target_metric
1,105
2,120
4,95
5,110
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
