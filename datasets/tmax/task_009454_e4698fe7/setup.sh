#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gzip tar xz-utils
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/climate_raw/station1/2023
    mkdir -p /home/user/climate_raw/station2/2023/feb

    cat << 'EOF' > /home/user/climate_raw/station1/2023/jan.dat
[2023-01-05 14:00:00] - SENSOR_Alpha - OZONE_SPIKE - 155.2
[2023-01-05 15:00:00] - SENSOR_Alpha - TEMP_DROP - -5.0
[2023-01-06 09:00:00] - SENSOR_Beta - OZONE_SPIKE - 140.0
[2023-01-06 10:00:00] - SENSOR_Gamma - OZONE_SPIKE - 150.0
EOF

    cat << 'EOF' > /home/user/climate_raw/station2/2023/feb/data.dat
[2023-02-10 11:30:00] - SENSOR_Beta - OZONE_SPIKE - 160.5
[2023-02-11 12:00:00] - SENSOR_Alpha - OZONE_SPIKE - 150.1
[2023-02-12 10:00:00] - SENSOR_Delta - WIND_GUST - 200.0
EOF

    gzip /home/user/climate_raw/station1/2023/jan.dat
    gzip /home/user/climate_raw/station2/2023/feb/data.dat

    cd /home/user
    tar -czf climate_raw.tar.gz climate_raw
    rm -rf climate_raw

    chmod -R 777 /home/user
