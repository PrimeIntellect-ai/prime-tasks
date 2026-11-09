#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang-go
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/network.json
{
  "A": ["B", "C"],
  "B": ["A", "D"],
  "C": ["A", "D", "E"],
  "D": ["B", "C", "E"],
  "E": ["C", "D"]
}
EOF

    cat << 'EOF' > /home/user/experimental_dist.json
{
  "A": 0.15,
  "B": 0.15,
  "C": 0.30,
  "D": 0.25,
  "E": 0.15
}
EOF

    chmod -R 777 /home/user
