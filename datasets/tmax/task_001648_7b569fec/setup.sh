#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip jq gawk
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/server_logs.jsonl
{"timestamp":"2023-10-01T10:00:00Z","user_id":"u1","response_time_ms":100,"message":"Start processing\x2Fok"}
{"timestamp":"2023-10-01T10:00:01Z","user_id":"u2","response_time_ms":200,"message":"Hello"}
{"timestamp":"2023-10-01T10:00:02Z","user_id":"u1","response_time_ms":150,"message":"Next step"}
{"timestamp":"2023-10-01T10:00:03Z","user_id":"u1","response_time_ms":null,"message":"Missing\xA9time"}
{"timestamp":"2023-10-01T10:00:04Z","user_id":"u3","response_time_ms":null,"message":"First request null"}
{"timestamp":"2023-10-01T10:00:05Z","user_id":"u1","response_time_ms":200,"message":"Done"}
{"timestamp":"2023-10-01T10:00:06Z","user_id":"u2","response_time_ms":210,"message":"World"}
EOF

    chmod -R 777 /home/user
