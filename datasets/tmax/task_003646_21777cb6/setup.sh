#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest numpy

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/target_cov.json
[
  [4.0, 1.2, -0.8],
  [1.2, 2.0, 0.5],
  [-0.8, 0.5, 1.0]
]
EOF

    chmod -R 777 /home/user
