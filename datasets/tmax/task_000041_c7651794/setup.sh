#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip systemd
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/.config/systemd/user
    mkdir -p /home/user/scripts
    mkdir -p /home/user/.config/micro-proxy/sites-available
    mkdir -p /home/user/.config/micro-proxy/sites-enabled
    mkdir -p /home/user/proxy-logs

    cat << 'EOF' > /home/user/scripts/micro_proxy.py
import sys, json, time
if len(sys.argv) < 2:
    print("Missing config file argument")
    sys.exit(1)
try:
    with open(sys.argv[1]) as f:
        config = json.load(f)
except Exception as e:
    print(f"Failed to load config: {e}")
    sys.exit(1)
print(f"Proxy started on port {config.get('listen_port')}")
while True:
    time.sleep(10)
EOF

    cat << 'EOF' > /home/user/scripts/storage-monitor.sh
#!/bin/bash
mkdir -p /home/user/.config/micro-proxy/sites-enabled
mkdir -p /home/user/.config/micro-proxy/sites-available
mkdir -p /home/user/proxy-logs

SIZE=$(du -m /home/user/proxy-logs | cut -f1)
if [ "$SIZE" -gt 50 ]; then
    echo "Error: Storage quota exceeded for logs ($SIZE MB > 50 MB limit)." >&2
    exit 1
fi
exit 0
EOF
    chmod +x /home/user/scripts/storage-monitor.sh

    cat << 'EOF' > /home/user/.config/systemd/user/micro-proxy.service
[Unit]
Description=Micro Reverse Proxy

[Service]
Type=simple
ExecStartPre=/home/user/scripts/storage-monitor.sh
ExecStart=/usr/bin/python3 /home/user/scripts/micro_proxy.py /home/user/.config/micro-proxy/sites-enabled/default.conf
Restart=on-failure
EOF

    cat << 'EOF' > /home/user/.config/micro-proxy/sites-available/default.conf
{
  "listen_port": 8080,
  "backends": ["http://127.0.0.1:8081", "http://127.0.0.1:8082"]
}
EOF

    ln -s /home/user/.config/micro-proxy/sites-available/defualt.conf /home/user/.config/micro-proxy/sites-enabled/default.conf

    dd if=/dev/zero of=/home/user/proxy-logs/old_requests.log bs=1M count=60

    chmod -R 777 /home/user
