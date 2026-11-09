#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/tokens.txt
eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJ1c2VybmFtZSI6ImFsaWNlIiwicm9sZSI6InVzZXIiLCJjcmVkaXRfY2FyZCI6IjEyMzQtNTY3OC05MDEyLTM0NTYifQ.ZmFrZV9zaWdfMQ
eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJ1c2VybmFtZSI6ImJvYiIsInJvbGUiOiJndWVzdCIsImNyZWRpdF9jYXJkIjoiOTk5OS04ODg4LTc3NzctNjY2NiJ9.ZmFrZV9zaWdfMg
eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJ1c2VybmFtZSI6ImNoYXJsaWUiLCJyb2xlIjoidXNlciIsImRlcGFydG1lbnQiOiJzYWxlcyJ9.ZmFrZV9zaWdfMw
EOF

    chmod -R 777 /home/user
