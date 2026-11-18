#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip ffmpeg golang
    pip3 install pytest

    mkdir -p /app/corpus/clean /app/corpus/evil
    mkdir -p /home/user

    # Generate a dummy video
    ffmpeg -f lavfi -i testsrc=duration=10:size=320x240:rate=1 -c:v libx264 /app/drone_flight.mp4

    # Create clean corpus
    cat << 'EOF' > /app/corpus/clean/clean1.csv
timestamp_sec,latitude,longitude,altitude,status
0,45.0,-93.2,100.5,OK
1,45.1,-93.3,101.0,WARN
EOF

    # Create evil corpus
    cat << 'EOF' > /app/corpus/evil/evil1.csv
timestamp_sec,latitude,longitude,altitude,status
0,45.0,-93.2,100.5,OK
2,95.0,-93.2,100.0,OK
3,45.0,-200.0,100.0,OK
4,45.0,-93.2,-10.0,OK
5,45.0,-93.2,100.0,INVALID_STATUS
invalid,45.0,-93.2,100.0,OK
EOF

    # Create raw telemetry
    cat << 'EOF' > /app/raw_telemetry.csv
timestamp_sec,latitude,longitude,altitude,status
0,45.0,-93.2,100.5,OK
1,45.1,-93.3,101.0,WARN
2,99.9,0.0,10.0,OK
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user /app
