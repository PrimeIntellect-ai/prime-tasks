#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc libc6-dev
    pip3 install pytest

    mkdir -p /home/user/logs
    mkdir -p /home/user/tmp_chunks

    cat << 'EOF' > /home/user/logs/raw_events.jsonl
{"timestamp":"2023-10-24T08:15:30Z","event":"login","user":"admin\u0021"}
{"timestamp":"2023-10-24T08:15:20Z","event":"logout","user":"admin\u0021"}
{"timestamp":"2023-10-24T08:16:05Z","event":"login","user":"test\u005Fuser"}
{"timestamp":"2023-10-23T12:00:00Z","event":"login","user":"sys\u0061dmin"}
{"timestamp":"2023-10-24T09:00:00Z","event":"heartbeat","user":"system"}
{"timestamp":"2023-10-24T08:15:35Z","event":"login","user":"h\u0061ck\u0065r"}
{"timestamp":"2023-10-24T08:17:00Z","event":"login","user":"norm\u0061l"}
{"timestamp":"2023-10-25T01:00:00Z","event":"login","user":"z\u006F\u006F"}
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
