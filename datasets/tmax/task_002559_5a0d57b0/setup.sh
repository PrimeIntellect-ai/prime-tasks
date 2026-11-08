#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip jq
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/api_logs

    cat << 'EOF' > /home/user/api_logs/req_A.json
{
  "service": "RustCompileAPI",
  "meta": {
    "version": "1.2.4"
  },
  "data": {
    "endpoints": ["/ast", "/compile", "/lint"]
  }
}
EOF

    cat << 'EOF' > /home/user/api_logs/req_B.json
{
  "service": "RustCompileAPI",
  "meta": {
    "version": "1.10.1"
  },
  "data": {
    "endpoints": ["/ast", "/compile", "/lint", "/format", "/macro-expand"]
  }
}
EOF

    cat << 'EOF' > /home/user/api_logs/req_C.json
{
  "service": "RustCompileAPI",
  "meta": {
    "version": "2.0.0-rc1"
  },
  "data": {
    "endpoints": ["/ast", "/build", "/lint", "/format"]
  }
}
EOF

    cat << 'EOF' > /home/user/api_logs/req_D.json
{
  "service": "OtherAPI",
  "meta": {
    "version": "3.0.0"
  },
  "data": {
    "endpoints": ["/status"]
  }
}
EOF

    cat << 'EOF' > /home/user/api_logs/req_E.json
{
  "service": "RustCompileAPI",
  "meta": {
    "version": "1.2.11"
  },
  "data": {
    "endpoints": ["/ast", "/compile", "/lint", "/debug"]
  }
}
EOF

    chmod -R 777 /home/user
