#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y \
        python3 \
        python3-pip \
        wget \
        curl \
        espeak \
        ffmpeg \
        build-essential

    pip3 install pytest pandas

    mkdir -p /app

    # Download cpp-httplib
    wget -qO /app/httplib.h https://raw.githubusercontent.com/yhirose/cpp-httplib/master/httplib.h

    # Generate audio instructions using espeak
    espeak -w /app/analyst_instructions.wav "The log encoding is iso-8859-1. Use a rolling window of three. Listen on port eight zero eight zero."

    # Generate system_metrics.bin
    python3 -c "
import pandas as pd
data = {
    'timestamp': [100, 101, 102, 103, 104],
    'zone_alpha': [10.0, 15.0, 14.0, 20.0, 22.0],
    'zone_beta': [5.0, 6.0, 8.0, 7.0, 10.0],
    'zone_gamma': [100.0, 90.0, 80.0, 85.0, 88.0]
}
df = pd.DataFrame(data)
df.to_csv('/app/system_metrics.bin', index=False, encoding='iso-8859-1')
"

    useradd -m -s /bin/bash user || true
    chmod -R 777 /app
    chmod -R 777 /home/user
