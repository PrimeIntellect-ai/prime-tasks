#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip curl build-essential rustc cargo
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/raw_transcript.log
[2023-11-01 14:05:00] <john> Hello world! 🚀
[14:05:02] <john> Hello world! 🚀
[2023-11-01 14:05:05] [cough] Bonjour le monde.
[14:05:06] Bonjour le monde.
[2023-11-01 14:05:10] <ali>   مرحبا   [music]
[2023-11-01 14:05:15] <yuki> こんにちは
[14:05:16] <yuki> こんにちは
[14:05:18] <sys> [applause] 
EOF

    chmod -R 777 /home/user
