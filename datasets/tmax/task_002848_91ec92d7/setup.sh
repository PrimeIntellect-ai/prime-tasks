#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip
pip3 install pytest

useradd -m -s /bin/bash user || true

mkdir -p /home/user/data
mkdir -p /home/user/output

cat << 'EOF' > /home/user/data/input.fasta
>seq1
ARND
>seq2
CQE
EOF

cat << 'EOF' > /home/user/data/test.fasta
>test1
M
EOF

cat << 'EOF' > /home/user/data/expected_test.json
{
  "test1": [
    256.67
  ]
}
EOF

chmod -R 777 /home/user
