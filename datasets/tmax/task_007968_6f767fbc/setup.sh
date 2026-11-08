#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip build-essential
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user
    cat << 'EOF' > /home/user/sensor_data.csv
10,S1,ERROR-1A4,10.0
20,S1,ERROR-XYZ,99.9
30,S1,ERROR-B22,20.0
40,S1,WARN-1A4,88.8
50,S1,ERROR-C33,30.0
60,S1,ERROR-D44,40.0
15,S2,ERROR-000,5.0
25,S2,ERROR-111,15.0
5,S2,ERROR-AAA,25.0
80,S3,ERROR-A,10.0
90,S3,ERROR-1234,10.0
EOF

    chmod -R 777 /home/user
