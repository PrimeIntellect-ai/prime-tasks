#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest pandas

    mkdir -p /home/user
    cat << 'EOF' > /home/user/sensor_data.csv
timestamp,sensor_id,temperature,humidity,notes
2023-10-01T10:00:00Z,S1,22.0,40.0,Startup normal
2023-10-01T10:02:00Z,S2,10.0,80.0,Initial reading
2023-10-01T10:05:00Z,S1,24.0,42.0,"Slight breeze
door opened"
2023-10-01T10:10:00Z,S1,26.0,44.0,All good
2023-10-01T10:15:00Z,S1,28.0,46.0,Getting warmer
2023-10-01T10:20:00Z,S1,100.0,50.0,ERROR SPIKE
2023-10-01T10:22:00Z,S2,12.0,85.0,"Damp
Very damp"
2023-10-01T10:25:00Z,S1,30.0,48.0,Recovered
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
