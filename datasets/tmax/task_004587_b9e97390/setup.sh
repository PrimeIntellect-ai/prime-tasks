#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip espeak ffmpeg
    pip3 install pytest

    # Create directories
    mkdir -p /app/corpus/clean
    mkdir -p /app/corpus/evil

    # Generate audio recording
    espeak -w /app/pager_recording.wav "Critical alert. Floating point truncation is causing database journal corruption. You must round all timezone offsets to exactly four decimal places before validation. After rounding, only allow offsets that are exact multiples of zero point two five hours. Reject everything else."

    # Create clean corpus files
    cat << 'EOF' > /app/corpus/clean/clean1.json
{"tz_offset_hours": 5.25}
EOF
    cat << 'EOF' > /app/corpus/clean/clean2.json
{"tz_offset_hours": 5.250000000000001}
EOF
    cat << 'EOF' > /app/corpus/clean/clean3.json
{"tz_offset_hours": 0.0}
EOF
    cat << 'EOF' > /app/corpus/clean/clean4.json
{"tz_offset_hours": -4.75}
EOF
    cat << 'EOF' > /app/corpus/clean/clean5.json
{"tz_offset_hours": -4.7499999999999}
EOF

    # Create evil corpus files
    cat << 'EOF' > /app/corpus/evil/evil1.json
{"tz_offset_hours": 5.26}
EOF
    cat << 'EOF' > /app/corpus/evil/evil2.json
{"tz_offset_hours": 5.333333333}
EOF
    cat << 'EOF' > /app/corpus/evil/evil3.json
{"tz_offset_hours": 1.2499}
EOF
    cat << 'EOF' > /app/corpus/evil/evil4.json
{"tz_offset_hours": -4.7501}
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
