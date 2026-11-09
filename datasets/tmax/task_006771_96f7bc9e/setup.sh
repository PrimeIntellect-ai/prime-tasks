#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    mkdir -p /home/user/data

    cat << 'EOF' > /home/user/data/edges.json
[
  {"src": "N1", "dst": "N2"},
  {"src": "N1", "dst": "N3"},
  {"src": "N1", "dst": "N4"},
  {"src": "N2", "dst": "N3"},
  {"src": "N2", "dst": "N4"},
  {"src": "N3", "dst": "N1"},
  {"src": "N5", "dst": "N1"},
  {"src": "N5", "dst": "N2"},
  {"src": "N6", "dst": "N6"},
  {"src": "N7", "dst": "N8"},
  {"src": "N8", "dst": "N7"}
]
EOF

    cat << 'EOF' > /home/user/data/nodes.json
{
  "N1": {"name": "Alpha", "cluster": "C1"},
  "N2": {"name": "Bravo", "cluster": "C1"},
  "N3": {"name": "Charlie", "cluster": "C2"},
  "N4": {"name": "Delta", "cluster": "C2"},
  "N5": {"name": "Echo", "cluster": "C3"},
  "N6": {"name": "Foxtrot", "cluster": "C4"},
  "N7": {"name": "Golf", "cluster": "C5"},
  "N8": {"name": "Hotel", "cluster": "C5"}
}
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
