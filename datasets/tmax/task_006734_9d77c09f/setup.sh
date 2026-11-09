#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++
    pip3 install pytest

    mkdir -p /home/user/data
    mkdir -p /home/user/output

    cat << 'EOF' > /home/user/data/temp.csv
timestamp,temperature,notes
2023-10-01T10:01:15Z,20.5,"Normal operation"
2023-10-01T10:03:10Z,21.5,"Slight
spike
observed"
2023-10-01T10:06:05Z,19.0,"Multi
line
note"
2023-10-01T10:08:59Z,21.0,"End of period"
2023-10-01T10:12:00Z,22.0,"No humidity data for this bucket"
EOF

    cat << 'EOF' > /home/user/data/humidity.csv
timestamp,humidity,notes
2023-10-01T10:02:15Z,50.0,"Ok"
2023-10-01T10:04:10Z,60.0,"Ok
really"
2023-10-01T10:05:00Z,55.0,"Start of
bad period"
2023-10-01T10:07:05Z,65.0,"Bad
Sensor"
2023-10-01T10:15:00Z,70.0,"No temp data for this bucket"
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
