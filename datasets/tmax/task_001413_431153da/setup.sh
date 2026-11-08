#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip xxd coreutils
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/generate_payload.py
#!/usr/bin/env python3
import base64
import binascii

def encode_node(node_id, data, child_id):
    hex_data = binascii.hexlify(data.encode('utf-8')).decode('utf-8')
    b64_data = base64.b64encode(data.encode('utf-8')).decode('utf-8')
    return f"{node_id}:{hex_data}-{b64_data}_{child_id}"

out = []
out.append(encode_node("01", "AlphaNode", "02"))
out.append(encode_node("02", "BetaNode", "03"))
out.append(encode_node("03", "GammaTerminal", "00"))
print("|".join(out))
EOF

    chmod +x /home/user/generate_payload.py
    chmod -R 777 /home/user
