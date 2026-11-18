#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip binutils coreutils
    pip3 install pytest

    mkdir -p /home/user

    cat << 'EOF' > /home/user/service.log
[2023-10-25T18:44:50Z] INFO Initialization complete.
[2023-10-25T18:44:51Z] INFO Successfully processed event ID: EVT-8918
[2023-10-25T18:44:53Z] INFO Successfully processed event ID: EVT-8919
[2023-10-25T18:44:56Z] INFO Successfully processed event ID: EVT-8920
[2023-10-25T18:44:59Z] INFO Successfully processed event ID: EVT-8921
EOF

    dd if=/dev/urandom of=/home/user/core.dump bs=1K count=1024 2>/dev/null
    echo "thread 'main' panicked at 'called \`Result::unwrap()\` on an \`Err\` value: ParseError(Invalid timezone offset: +28:00 for timestamp 2023-10-25T18:45:00+28:00)', src/parser.rs:42:18" >> /home/user/core.dump
    echo "note: run with \`RUST_BACKTRACE=1\` environment variable to display a backtrace" >> /home/user/core.dump
    dd if=/dev/urandom bs=1K count=512 >> /home/user/core.dump 2>/dev/null

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
