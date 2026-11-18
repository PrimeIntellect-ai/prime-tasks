#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++ wget
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user

    cat << 'EOF' > /home/user/input_logs.jsonl
{"ts": 1698141600, "svc": "auth", "status": 200, "rt": 100}
{"ts": 1698141610, "svc": "web", "status": 200, "rt": 50}
{"ts": 1698141630, "svc": "auth", "status": 500, "rt": 600}
invalid json line here
{"ts": 1698141659, "svc": "auth", "status": 200, "rt": 800}
{"ts": 1698141660, "svc": "auth", "status": 200, "rt": 200}
{"ts": 1698141665, "svc": "auth", "status": 401, "rt": 900}
{"ts": 1698141700, "svc": "auth", "status": 200, "rt": 100}
{"ts": 1698141705, "svc": "auth", "status": 600, "rt": 5000}
{"ts": 1698141720, "svc": "auth", "status": 200, "rt": 700}
{"ts": 1698141730, "svc": "auth", "status": 503, "rt": 1300}
EOF

    python3 -c '
with open("/home/user/alert_template.txt", "w") as f:
    f.write("## Alert for Bucket {ts}\n".replace("{ts}", "{" + "{ts}" + "}"))
    f.write("- Average Response Time: {avg}ms\n".replace("{avg}", "{" + "{avg}" + "}"))
    f.write("- Rolling Average at bucket end: {rolling}ms\n".replace("{rolling}", "{" + "{rolling}" + "}"))
    f.write("- Request Count: {count}\n".replace("{count}", "{" + "{count}" + "}"))
'

    chown -R user:user /home/user
    chmod -R 777 /home/user
