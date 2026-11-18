#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++
    pip3 install pytest

    mkdir -p /home/user

    cat << 'EOF' > /home/user/sensors.tsv
sensor_id	status
1	active
2	inactive
3	active
EOF

    cat << 'EOF' > /home/user/measurements.csv
timestamp,sensor_id,value,notes
1000,1,10.0,"Start"
1005,1,12.0,"Normal"
1010,1,14.0,"Note with
newline"
1015,2,99.0,"Ignore"
1020,3,5.0,"Okay"
1025,1,16.0,"End"
1030,3,10.0,"Another
newline
here"
1035,3,15.0,"Done"
1040,1,18.0,"Final"
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
