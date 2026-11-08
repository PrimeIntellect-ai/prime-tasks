#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip
pip3 install pytest

useradd -m -s /bin/bash user || true

cat << 'EOF' > /tmp/setup.py
import base64

manifest_text = """[Component: scripts-py]
Language: Python
Path: /home/user/src/py-scripts
Deps: cli-rust, backend-go

[Component: backend-go]
Language: Go
Path: /home/user/src/go-backend
Deps: none

[Component: aggregator-go]
Language: Go
Path: /home/user/src/go-agg
Deps: backend-go, scripts-py

[Component: cli-rust]
Language: Rust
Path: /home/user/src/rust-cli
Deps: backend-go
"""

encoded_bytes = manifest_text.encode('utf-16-le')
b64_str = base64.b64encode(encoded_bytes).decode('ascii')

with open('/home/user/manifest.b64', 'w') as f:
    f.write(b64_str)
EOF

python3 /tmp/setup.py
rm /tmp/setup.py

chmod -R 777 /home/user
