#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip ffmpeg gcc libc-dev
    pip3 install pytest

    mkdir -p /app/corpora/clean /app/corpora/evil /app/corpora/golden

    # Generate a dummy video fixture
    ffmpeg -f lavfi -i testsrc=duration=5:size=640x480:rate=30 -c:v libx264 /app/conveyor.mp4 -y

    # Generate clean corpus
    cat << 'EOF' > /app/corpora/clean/sensor_01.csv
0.000000,sensA,10.5
0.033333,sensA,11.2
0.066667,sensA,10.8
EOF

    # Generate evil corpus
    cat << 'EOF' > /app/corpora/evil/sensor_02.csv
0.000000,sensB,20.1
INVALID,sensB,20.1
0.033333,sensB,20.5
0.000000,sensB,99.9
0.066667,sensB,malformed
0.066667,sensB,21.0
EOF

    # Create golden reference for evil
    cat << 'EOF' > /app/corpora/golden/sensor_02.csv
0.000000,sensB,20.1
0.033333,sensB,20.5
0.066667,sensB,21.0
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
