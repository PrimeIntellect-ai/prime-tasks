#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip protobuf-compiler
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/pipeline.dsl
PID CI-8492
STP Build | ZWNobyAiQnVpbGRpbmci
STP Test | bWFrZSB0ZXN0
STP Deploy | Li9kZXBsb3kuc2g=
EOF

    chmod -R 777 /home/user
