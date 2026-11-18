#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang-go
    pip3 install pytest

    mkdir -p /home/user/docs/setup /home/user/docs/advanced /home/user/dist

    cat << 'EOF' > /home/user/config.json
{
  "source_dir": "/home/user/docs",
  "output_dir": "/home/user/dist",
  "max_lines_per_chunk": 50,
  "merge_groups": {
    "getting_started.md": ["intro.md", "setup/install.md"],
    "api_ref.md": ["advanced/api1.md", "advanced/api2.md"]
  }
}
EOF

    seq 1 30 > /home/user/docs/intro.md
    seq 31 70 > /home/user/docs/setup/install.md
    seq 1 120 > /home/user/docs/advanced/networking.md
    seq 1 20 > /home/user/docs/advanced/api1.md
    seq 21 30 > /home/user/docs/advanced/api2.md

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
