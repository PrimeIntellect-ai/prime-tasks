#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc build-essential
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/artifacts.hexar
=== FILE: alpha.bin ===
0A 0B 00 00 00
0C 00 00 00 00
0D 00 00 00
=== END ===
=== FILE: beta.bin ===
FF AA 00 00 00
BB 00 00 CC
=== END ===
=== FILE: gamma.bin ===
11 22 33 44 55
=== END ===
EOF

    chmod -R 777 /home/user
