#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip curl jq socat netcat binutils
    pip3 install pytest

    mkdir -p /app/audio /app/data/telemetry

    # Generate the audio fixture with embedded text
    echo -ne "RIFF\x24\x00\x00\x00WAVEfmt \x10\x00\x00\x00\x01\x00\x01\x00\x44\xAC\x00\x00\x88\x58\x01\x00\x02\x00\x10\x00data\x00\x00\x00\x00" > /app/audio/transmission.wav
    echo -ne "TRANSCRIPT_DATA:Mötörhead résumé café \x80\x93 coördinator" >> /app/audio/transmission.wav

    # Generate telemetry data
    cat << 'EOF' > /app/data/telemetry/sensor_001.csv
1700000000,10.0
1700000003,15.5
1700000005,12.0
EOF

    cat << 'EOF' > /app/data/telemetry/sensor_002.csv
1700000001,8.0
1700000008,22.4
1700000010,21.0
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user /app
