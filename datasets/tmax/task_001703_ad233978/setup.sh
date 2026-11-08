#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip jq gawk coreutils sed grep
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/gateway.log
{"timestamp": "2023-10-01T10:00:00Z", "ip": "192.168.1.10", "path": "/api/data", "auth_header": "Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJ1c2VyIjoidGVzdCJ9.sig1", "status": 200}
{"timestamp": "2023-10-01T10:05:00Z", "ip": "10.0.0.5", "path": "/api/admin", "auth_header": "Bearer eyJhbGciOiJub25lIiwidHlwIjoiSldUIn0.eyJ1c2VyIjoiYWRtaW4iLCJyb2xlIjoiYWRtaW4ifQ.", "status": 200}
{"timestamp": "2023-10-01T10:06:00Z", "ip": "10.0.0.5", "path": "/api/admin", "auth_header": "Bearer eyJhbGciOiJOT05FIiwidHlwIjoiSldUIn0.eyJ1c2VyIjoiYWRtaW4iLCJyb2xlIjoiYWRtaW4ifQ.", "status": 200}
{"timestamp": "2023-10-01T10:07:00Z", "ip": "172.16.0.12", "path": "/api/admin", "auth_header": "Bearer eyJhbGciOiJOb25lIiwidHlwIjoiSldUIn0.eyJ1c2VyIjoiYWRtaW4iLCJyb2xlIjoiYWRtaW4ifQ.", "status": 401}
{"timestamp": "2023-10-01T10:10:00Z", "ip": "203.0.113.42", "path": "/api/admin", "auth_header": "Bearer eyJhbGciOiJOT05FIiwidHlwIjoiSldUIn0.eyJ1c2VyIjoiYWRtaW4ifQ.", "status": 200}
EOF

    chmod -R 777 /home/user
