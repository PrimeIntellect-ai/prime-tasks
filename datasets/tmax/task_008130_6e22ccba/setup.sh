#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip jq gawk bc sed
pip3 install pytest

useradd -m -s /bin/bash user || true

cat << 'EOF' > /home/user/spatial_data.jsonl
{"x": 2.0, "y": 4.0, "label": "A_\u03b1"}
{"x": 4.0, "y": "NaN", "label": "B_\u03b2"}
{"x": 6.0, "y": 12.0, "label": "C_\u03b3"}
{"x": 8.0, "y": "NaN", "label": "D_\u03b4"}
{"x": 10.0, "y": 0.0, "label": "E_\u03b5"}
EOF

chmod -R 777 /home/user
