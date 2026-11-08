#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip sqlite3 gcc
    pip3 install pytest

    # Create directories
    mkdir -p /app
    mkdir -p /home/user

    # Create dummy audio file
    touch /app/dataset_dictation.wav

    # Create mock whisper CLI to avoid 600s timeout from downloading PyTorch
    cat << 'EOF' > /usr/local/bin/whisper
#!/bin/bash
for arg in "$@"; do
    if [[ "$arg" == *.wav || "$arg" == *.mp3 ]]; then
        base=$(basename "$arg")
        base="${base%.*}"
        TEXT="The system has several connections. user_logs joins with session_data. session_data joins with telemetry. user_logs joins with accounts. accounts joins with billing_info. billing_info joins with payment_gateways. telemetry joins with performance_metrics. accounts joins with preferences."
        echo "$TEXT" > "${base}.txt"
        echo "$TEXT" > "${base}.srt"
        echo "$TEXT" > "${base}.vtt"
        echo "$TEXT" > "${base}.tsv"
    fi
done
EOF
    chmod +x /usr/local/bin/whisper

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
