#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip espeak-ng ffmpeg
    pip3 install pytest

    mkdir -p /app

    # Generate the audio file
    espeak-ng -w /app/research_log.wav "Today is the 14th of October. The temperature in the greenhouse dropped to 15 degrees Celsius overnight. The humidity sensors in sector A are showing anomalous readings. I suspect water condensation on the circuit boards. I recalibrated the deep learning model for the visual anomaly detection system. It is now achieving 94 percent accuracy on the validation set. I need to order more nutrient solution for the hydroponics bay tomorrow."

    # Create the search queries file
    cat << 'EOF' > /app/search_queries.txt
What is the status of the humidity sensors?
How well is the visual anomaly detection model performing?
What supplies need to be ordered?
EOF

    # Create user and pipeline directory
    useradd -m -s /bin/bash user || true
    mkdir -p /home/user/pipeline

    # Set permissions
    chmod -R 777 /home/user /app
