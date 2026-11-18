#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip cargo rustc
    pip3 install pytest PyJWT

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/jwt_logs.txt
eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiJhbGljZSIsImlhdCI6MTY5OTk5OTk5OX0.dummy_signature_alice
eyJhbGciOiJub25lIn0.eyJzdWIiOiJib2IifQ.
eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiJjaGFybGllIiwiaWF0IjoxNjk5OTk5OTk5fQ.dummy_signature_charlie
eyJhbGciOiJub25lIn0.eyJzdWIiOiJkaWFuYSJ9.
EOF

    chmod -R 777 /home/user
