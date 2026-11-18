#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip
pip3 install pytest

useradd -m -s /bin/bash user || true

mkdir -p /home/user/manifests
mkdir -p /home/user/data
mkdir -p /home/user/public
echo "hello world" > /home/user/public/index.html

cat << 'EOF' > /home/user/manifests/db.json
{
  "name": "db",
  "command": "sleep 100",
  "depends_on": []
}
EOF

cat << 'EOF' > /home/user/manifests/backend.json
{
  "name": "backend",
  "command": "sleep 100",
  "depends_on": ["db"]
}
EOF

cat << 'EOF' > /home/user/manifests/frontend.json
{
  "name": "frontend",
  "command": "sleep 100",
  "depends_on": ["backend"]
}
EOF

cat << 'EOF' > /home/user/operator.py
#!/usr/bin/env python3
import os
import json
import sys

MANIFEST_DIR = "/home/user/manifests"
LAUNCHER_PATH = "/home/user/launcher.sh"
DATA_DIR = "/home/user/data"
LOG_PATH = "/home/user/operator.log"

def main():
    # TODO: Implement storage check here

    services = []
    for f in os.listdir(MANIFEST_DIR):
        if f.endswith(".json"):
            with open(os.path.join(MANIFEST_DIR, f)) as jf:
                services.append(json.load(jf))

    # TODO: Implement dependency sorting here (currently random order)
    ordered_services = services 

    with open(LAUNCHER_PATH, "w") as f:
        f.write("#!/bin/bash\n")
        f.write("rm -f /home/user/start_order.txt\n")
        for svc in ordered_services:
            # TODO: write to start_order.txt
            f.write(f"{svc['command']} &\n")
            f.write("sleep 1\n")

    os.chmod(LAUNCHER_PATH, 0o755)

if __name__ == "__main__":
    main()
EOF

chmod +x /home/user/operator.py
chown -R user:user /home/user/
chmod -R 777 /home/user
