#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/build_logs

    cat << 'EOF' > /home/user/build_logs/worker_1.log
[2023-10-25T14:32:01.123Z] [Worker-1] Compiling main.cpp
[2023-10-25T14:32:03.442Z] [Worker-1] Compiling network.cpp
[2023-10-25T14:32:06.100Z] [Worker-1] Linking target mobile_app
EOF

    cat << 'EOF' > /home/user/build_logs/worker_2.log
[2023-10-25T14:32:00.001Z] [Worker-2] Fetching dependencies
[2023-10-25T14:32:02.555Z] [Worker-2] Building AwesomeMath
[2023-10-25T14:32:07.888Z] [Worker-2] ld: library not found for -lTelemetryEngineX
[2023-10-25T14:32:08.001Z] [Worker-2] Build failed.
EOF

    cat << 'EOF' > /home/user/build_logs/worker_3.log
[2023-10-25T14:32:01.888Z] [Worker-3] Compiling ui_components.cpp
[2023-10-25T14:32:04.111Z] [Worker-3] Optimizing assets
[2023-10-25T14:32:05.999Z] [Worker-3] Asset optimization complete
EOF

    chown -R user:user /home/user/build_logs
    chmod -R 777 /home/user
