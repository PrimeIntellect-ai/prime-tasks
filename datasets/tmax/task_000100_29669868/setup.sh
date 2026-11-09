#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip espeak
    pip3 install pytest

    mkdir -p /app

    # Generate the instruction audio using espeak
    espeak -w /app/instruction.wav "Subtract forty two from all results."

    # Create the math data CSV
    cat << 'EOF' > /app/math_data.csv
id,expression
101,½ * ⑧
102,⑳ / Ⅳ
103,５ + ７
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
