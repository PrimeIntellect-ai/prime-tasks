#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip zip espeak
    pip3 install pytest

    mkdir -p /app/corpora/incoming

    # Generate reference audio
    espeak -w /app/reference_interview.wav "Subject confirmed the anomaly originates from sector 7G."

    # Create clean zip
    mkdir -p /tmp/clean_zip
    echo "Event 1\nDetails 1\n---\nEvent 2\nDetails 2" > /tmp/clean_zip/events.log
    cd /tmp/clean_zip && zip /app/corpora/incoming/clean_1.zip events.log

    # Create evil zip with Zip Slip payload
    cat << 'EOF' > /tmp/make_evil.py
import zipfile
with zipfile.ZipFile('/app/corpora/incoming/evil_1.zip', 'w') as z:
    z.writestr('../../../home/user/.bashrc', 'echo "hacked"')
EOF
    python3 /tmp/make_evil.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
