#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/legacy_project
    cat << 'EOF' > /home/user/legacy_project/archive.json
{
  "decoder_asm": "MOV R1, 100\nSUB R1, 20\nSHR R1, 2\nXOR R1, 11\n",
  "files": [
    {
      "name_b64": "Y29uZmlnLnlhbWw=",
      "content_hex": "8f8e9193593f574f574f29878e9293593f8b8e82808b878e9293"
    },
    {
      "name_b64": "bWFpbi5weQ==",
      "content_hex": "8f91888d93474667848b8b8e3f609182878895844648"
    }
  ]
}
EOF

    chmod -R 777 /home/user
