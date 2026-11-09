#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/services

    cat << 'EOF' > /home/user/mini_init.py
import sys, os, time, subprocess, configparser

SERVICES_DIR = "/home/user/services"

def load_services():
    services = {}
    for f in os.listdir(SERVICES_DIR):
        if f.endswith(".service"):
            config = configparser.ConfigParser()
            config.read(os.path.join(SERVICES_DIR, f))
            services[f] = {
                'exec': config.get('Service', 'ExecStart', fallback=None),
                'after': config.get('Unit', 'After', fallback=None)
            }
    return services

def start_services():
    services = load_services()
    started = set()

    # Very simple dependency resolver
    def start_service(name):
        if name in started: return True
        svc = services[name]
        if svc['after'] and svc['after'] not in started:
            if not start_service(svc['after']):
                return False

        print(f"Starting {name}...")
        cmd = svc['exec'].split()
        proc = subprocess.run(cmd, capture_output=True, text=True)
        if proc.returncode != 0:
            print(f"Failed to start {name}: {proc.stderr}")
            sys.exit(1)
        started.add(name)
        return True

    for s in services:
        start_service(s)
    print("All services started successfully.")

if __name__ == '__main__':
    if len(sys.argv) > 1 and sys.argv[1] == 'start':
        start_services()
EOF

    cat << 'EOF' > /home/user/auth_daemon.py
import sys, json, os
with open("/home/user/auth_status.json", "w") as f:
    json.dump({"status": "running"}, f)
sys.exit(0)
EOF

    cat << 'EOF' > /home/user/worker_daemon.py
import sys, os
if not os.path.exists("/home/user/auth_status.json"):
    sys.stderr.write("Connection refused: auth_server is not running\n")
    sys.exit(1)
sys.exit(0)
EOF

    cat << 'EOF' > /home/user/services/auth_server.service
[Unit]
Description=Auth Server

[Service]
ExecStart=python3 /home/user/auth_daemon.py
EOF

    cat << 'EOF' > /home/user/services/app_worker.service
[Unit]
Description=App Worker

[Service]
ExecStart=python3 /home/user/worker_daemon.py
EOF

    cat << 'EOF' > /home/user/raw_users.txt
alice:admin:1001
bob:user:1002
invalid_line_missing_uid
charlie:user:1003
david:guest:not_an_int
eve:admin:1004:extra_field
EOF

    chmod -R 777 /home/user
