#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang-go
    pip3 install pytest

    mkdir -p /home/user/workspace

    cat << 'EOF' > /home/user/workspace/packages.json
{
  "core-app": {
    "size": 30,
    "depends_on": ["libA"],
    "conflicts_with": []
  },
  "libA": {
    "size": 20,
    "depends_on": [],
    "conflicts_with": ["libB"]
  },
  "libB": {
    "size": 40,
    "depends_on": [],
    "conflicts_with": ["libA"]
  },
  "plugin1": {
    "size": 50,
    "depends_on": ["core-app"],
    "conflicts_with": []
  },
  "plugin2": {
    "size": 60,
    "depends_on": ["core-app"],
    "conflicts_with": ["plugin1"]
  },
  "util": {
    "size": 10,
    "depends_on": [],
    "conflicts_with": []
  }
}
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
