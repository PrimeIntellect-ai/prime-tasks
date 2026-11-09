#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip xxd coreutils
    pip3 install pytest

    mkdir -p /home/user/logs
    cat << 'EOF' > /home/user/logs/services.log
1698825600 [app] INFO Starting reporting job 101
2023-11-01T08:00:05Z [formatter] WARN Unrecognized format variant requested
1698825608 [app] INFO Sending payload to formatter
2023-11-01T08:00:09Z [formatter] INFO Processing payload chunk 1
1698825610 [app] ERROR Formatter crashed with payload: 4552524f523a20436f7272757074206d61676963206279746573
1698825612 [app] INFO Cleaning up job 101
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
