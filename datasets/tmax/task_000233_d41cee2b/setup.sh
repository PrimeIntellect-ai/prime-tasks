#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip espeak ffmpeg
    pip3 install pytest pandas numpy

    # Create the app directory and generate the audio file
    mkdir -p /app
    espeak -w /app/telemetry_data.wav "Time 0. Alpha 12.0. Beta 50.0. Time 10. Alpha 14.5. Beta 48.2. Time 20. Alpha missing. Beta 47.0. Time 30. Alpha 17.5. Beta missing. Time 40. Alpha 18.0. Beta 45.0. Time 50. Alpha 19.5. Beta 44.5. Time 60. Alpha 20.0. Beta 44.0."

    # Create user
    useradd -m -s /bin/bash user || true

    # Set permissions
    chmod -R 777 /home/user
    chmod -R 777 /app
