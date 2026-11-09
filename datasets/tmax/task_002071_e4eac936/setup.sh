#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc libc6-dev curl
    pip3 install pytest requests

    mkdir -p /app/data /app/audio

    cat << 'EOF' > /app/data/historical_metrics.csv
run_id,inference_time_ms,accuracy
1,120,0.85
2,150,0.82
3,90,0.88
4,200,0.75
EOF

    dd if=/dev/urandom of=/app/audio/eval_sample.wav bs=1000 count=1500

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
