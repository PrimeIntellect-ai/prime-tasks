#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip redis-server curl gawk tzdata
    pip3 install pytest redis flask

    mkdir -p /app
    mkdir -p /home/user

    # Oracle script
    cat << 'EOF' > /app/oracle_normalize.sh
#!/bin/bash
export TZ=UTC
awk -F' \\| ' '
BEGIN { OFS="," }
{
    if (NF != 4) next;
    timestamp = $1
    service = $2
    operation = $3
    config_pair = $4

    if (operation != "CREATE" && operation != "MODIFY" && operation != "DELETE") next;

    split(config_pair, kv, "=")
    key = kv[1]
    value = kv[2]
    for (i=3; i<=length(kv); i++) {
        value = value "=" kv[i]
    }

    if (tolower(key) ~ /secret/) next;

    cmd = "date -d \"" timestamp "\" +%s"
    cmd | getline epoch
    close(cmd)

    print epoch, service, operation, key, length(value)
}' | sort -t, -k1,1n -k2,2
EOF
    chmod +x /app/oracle_normalize.sh

    # Dummy emitter
    cat << 'EOF' > /app/emitter.py
import json
import time
import redis
import sys

try:
    with open('/home/user/emitter.json') as f:
        config = json.load(f)
except Exception:
    config = {}

if config.get("output_type") == "redis":
    r = redis.Redis(host=config.get("redis_host", "localhost"), port=config.get("redis_port", 6379), db=0)
    while True:
        try:
            r.set("emitter_active", "true")
            r.set("last_ping", time.time())
        except:
            pass
        time.sleep(1)
else:
    while True:
        time.sleep(1)
EOF

    # Dummy dashboard
    cat << 'EOF' > /app/dashboard.py
from flask import Flask, jsonify
import os
import redis

app = Flask(__name__)

@app.route('/health')
def health():
    redis_url = None
    try:
        with open('/home/user/dashboard.env') as f:
            for line in f:
                if line.startswith('REDIS_URL='):
                    redis_url = line.strip().split('=', 1)[1]
    except Exception:
        pass

    if not redis_url:
        return jsonify({"status": "error", "redis_connected": False, "emitter_active": False}), 500

    try:
        r = redis.from_url(redis_url)
        r.ping()
        emitter_active = r.get("emitter_active") == b"true"
        return jsonify({"status": "ok", "redis_connected": True, "emitter_active": emitter_active})
    except Exception as e:
        return jsonify({"status": "error", "redis_connected": False, "emitter_active": False}), 500

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=8080)
EOF

    # Startup script
    cat << 'EOF' > /app/startup.sh
#!/bin/bash
redis-server --daemonize yes
python3 /app/emitter.py &
python3 /app/dashboard.py &
EOF
    chmod +x /app/startup.sh

    # Broken configs
    cat << 'EOF' > /home/user/emitter.json
{
  "output_type": "file",
  "file_path": "/dev/null",
  "redis_host": "",
  "redis_port": 0
}
EOF

    cat << 'EOF' > /home/user/dashboard.env
REDIS_URL=
EOF

    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user
    chmod -R 777 /home/user
