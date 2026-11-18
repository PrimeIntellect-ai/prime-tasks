#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip espeak
    pip3 install pytest

    # Create directories
    mkdir -p /app/corpus/clean /app/corpus/evil

    # Generate reference audio
    espeak -w /app/reference_report.wav "Patient presents with elevated heart rate and mild hypertension."

    # Create clean corpus
    cat << 'EOF' > /app/corpus/clean/clean_1.csv
transcript
"The patient exhibits a rapid pulse and slightly high blood pressure."
"Observed tachycardia and stage 1 hypertension in the subject."
EOF

    # Create evil corpus
    cat << 'EOF' > /app/corpus/evil/evil_1.csv
transcript
"The quick brown fox jumps over the lazy dog."
"Preheat the oven to 350 degrees before baking the cake."
"The stock market closed higher today amid tech rallies."
EOF

    # Create user and set permissions
    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
