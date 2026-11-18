#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip rustc cargo
    pip3 install pytest

    mkdir -p /home/user

    cat << 'EOF' > /home/user/locations.txt
Field report from January.
Sensor S1 is installed at origin (0.0, 0.0).
We moved S2 to (3.0, 4.0) yesterday after the storm.
S3 was found at (1.0, 1.0) partially covered in mud.
EOF

    cat << 'EOF' > /home/user/readings.csv
hour,sensor,temperature
0,S1,10.0
1,S1,12.0
3,S1,14.0
9,S1,20.0
0,S2,100.0
2,S2,120.0
4,S2,140.0
9,S2,200.0
0,S3,5.0
1,S3,5.0
5,S3,10.0
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
