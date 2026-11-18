#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip curl cron
    pip3 install pytest

    # Install Rust
    curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
    export PATH="$HOME/.cargo/bin:$PATH"

    # Also install rust system packages just in case or symlink
    apt-get install -y cargo rustc

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user
    cat << 'EOF' > /home/user/raw_translations.txt
2023-10-24T14:05:00Z|es|¡Hola!
2023-10-24T14:15:22Z|es|¡Hola!
2023-10-24T14:16:00Z|ja|こんにちは
2023-10-24T14:55:00Z|fr|Bonjour
2023-10-24T15:01:00Z|es|Adiós
2023-10-24T15:02:00Z|es|Adiós
2023-10-24T15:05:00Z|ja|さようなら
2023-10-24T15:05:00Z|ja|さようなら
2023-10-24T15:10:00Z|es|Adiós
EOF

    chown -R user:user /home/user
    chmod -R 777 /home/user
