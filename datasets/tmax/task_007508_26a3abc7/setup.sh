#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    mkdir -p /home/user/artifacts/logs/
    mkdir -p /home/user/artifacts/raw/

    # Create dummy binaries
    echo -n "success_data_1" > /home/user/artifacts/raw/app-1.0.bin
    echo -n "fail_data_1" > /home/user/artifacts/raw/app-1.1.bin
    echo -n "success_data_2" > /home/user/artifacts/raw/app-2.0.bin

    # Create log 1
    cat << 'EOF' > /home/user/artifacts/logs/build_server1.log
=== BUILD RECORD START ===
Date: 2023-10-01
Artifact: app-1.0.bin
Steps:
 - compile: ok
 - link: ok
Result: SUCCESS
=== BUILD RECORD END ===
Some garbage text between records.
=== BUILD RECORD START ===
Date: 2023-10-02
Artifact: app-1.1.bin
Steps:
 - compile: ok
 - link: error (missing symbol)
Result: FAILED
=== BUILD RECORD END ===
EOF

    # Create log 2
    cat << 'EOF' > /home/user/artifacts/logs/build_server2.log
=== BUILD RECORD START ===
Date: 2023-10-03
Artifact: app-2.0.bin
Steps:
 - compile: ok
 - link: ok
 - test: pass
Result: SUCCESS
=== BUILD RECORD END ===
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
