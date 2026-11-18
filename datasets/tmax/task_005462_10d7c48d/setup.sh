#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip ffmpeg nodejs npm espeak
    pip3 install pytest

    mkdir -p /app/audio
    espeak -w /app/audio/status_update.wav "The project alpha deployment is complete. System latency decreased by twenty milliseconds. We observed some anomalies in the database cluster. Please investigate the node memory usage."

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
