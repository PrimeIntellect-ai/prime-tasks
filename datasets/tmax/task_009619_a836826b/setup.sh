#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc libc6-dev
    pip3 install pytest

    mkdir -p /home/user/src /home/user/data /home/user/output

    cat << 'EOF' > /home/user/data/metadata.txt
tok_alpha
tok_beta
tok_gamma
EOF

    python3 -c "
import struct
with open('/home/user/data/embeddings.bin', 'wb') as f:
    # Vector 0: Norm 5.0
    f.write(struct.pack('<4f', 3.0, 0.0, 4.0, 0.0))
    # Vector 1: Norm 0.0 (anomalous)
    f.write(struct.pack('<4f', 0.0, 0.0, 0.0, 0.0))
    # Vector 2: Norm 10.0
    f.write(struct.pack('<4f', 0.0, 8.0, 6.0, 0.0))
"

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
