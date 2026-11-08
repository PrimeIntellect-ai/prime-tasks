#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip gawk bc
pip3 install pytest

useradd -m -s /bin/bash user || true

cat << 'EOF' > /home/user/benchmarks.csv
model_id,inference_ms,confidence_score
m1,120,0.85
m2,135,0.80
m3,-10,0.90
m4,110,0.88
m5,150,0.75
m6,foo,0.80
m7,140,0.78
EOF

chmod -R 777 /home/user
