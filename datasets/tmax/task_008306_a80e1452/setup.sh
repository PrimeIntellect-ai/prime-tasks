#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest jinja2

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/data /home/user/output

    cat << 'EOF' > /home/user/data/raw_events.jsonl
{"id": 1, "message": "System started successfully \u2713"}
{"id": 2, "message": "Error encountered: \uZZZZ unknown module"}
{"id": 3, "message": "System started successfully \u2713"}
{"id": 4, "message": "User login: admin"}
{"id": 5, "message": "Error encountered: \uZZZZ unknown module"}
{"id": 6, "message": "Cache flushed"}
{"id": 7, "message": "Warning: \uG123 invalid token"}
{"id": 8, "message": "User logout: admin"}
EOF

    # Create template file using Python to avoid Apptainer build variable syntax
    python3 -c '
with open("/home/user/data/template.md.j2", "w") as f:
    f.write("# Daily Event Report\n\nWe processed the following unique events today:\n\n{% for msg in messages %}\n* {" + "{ msg }}" + "\n{% endfor %}\n")
'

    chmod -R 777 /home/user
