#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip espeak ffmpeg
    pip3 install pytest pandas SpeechRecognition flask fastapi uvicorn requests pydub

    mkdir -p /app

    # Generate the audio file
    espeak -w /app/telemetry_alert.wav "Timestamp 1715000000, value 94.5. Timestamp 1715000060, value 98.2."

    # Create the CSV file
    cat << 'EOF' > /app/system_metrics.csv
timestamp,server_A_metric,server_B_metric,server_C_metric
1714999800,45.2,88.1,33.4
1714999860,46.0,91.5,34.0
1714999920,45.8,89.0,33.8
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
