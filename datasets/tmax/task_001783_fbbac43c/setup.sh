#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip curl
    pip3 install pytest flask fastapi uvicorn requests

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/manifests

    cat << 'EOF' > /home/user/manifests/service_a.json
{
  "service": "A",
  "deps": {
    "requests": "2.25.1",
    "numpy": "1.19.0",
    "pyyaml": "5.3"
  }
}
EOF

    cat << 'EOF' > /home/user/manifests/service_b.json
{
  "service": "B",
  "deps": {
    "requests": "2.26.0",
    "flask": "1.1.2",
    "pyyaml": "5.3"
  }
}
EOF

    cat << 'EOF' > /home/user/manifests/service_c.json
{
  "service": "C",
  "deps": {
    "numpy": "1.20.1",
    "pandas": "1.2.0"
  }
}
EOF

    chmod -R 777 /home/user
