#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip jq socat netcat-openbsd binutils
    pip3 install pytest pyinstaller

    mkdir -p /app/corpus/evil /app/corpus/clean /app/src

    # Create clean corpus
    cat << 'EOF' > /app/corpus/clean/1.json
{"uid": 12, "cmd": "build", "params": "mode=release&arch=amd64"}
EOF
    cat << 'EOF' > /app/corpus/clean/2.json
{"uid": 999, "cmd": "deploy", "params": "env=prod&region=us-east-1"}
EOF

    # Create evil corpus
    cat << 'EOF' > /app/corpus/evil/1.json
{"uid": 13, "cmd": "build", "params": "mode=release;rm -rf /"}
EOF
    cat << 'EOF' > /app/corpus/evil/2.json
{"uid": 14, "cmd": "b!uild", "params": "mode=release"}
EOF
    cat << 'EOF' > /app/corpus/evil/3.json
{"uid": 15, "cmd": "test", "params": "mode=release&arch=amd64|whoami"}
EOF
    cat << 'EOF' > /app/corpus/evil/4.json
{"uid": 16, "cmd": "run", "params": "mode=release&arch=amd64`ls`"}
EOF

    # Create Python script for the legacy binary
    cat << 'EOF' > /app/src/migrator.py
import sys
import json
import urllib.parse

def main():
    try:
        data = sys.stdin.read()
        if not data.strip():
            return
        j = json.loads(data)
        uid = int(j.get("uid", 0))
        cmd = str(j.get("cmd", ""))
        params = str(j.get("params", ""))

        user = f"U{uid:04d}"
        command = cmd.upper()

        config = dict(urllib.parse.parse_qsl(params))

        out = {
            "user": user,
            "command": command,
            "config": config
        }
        print(json.dumps(out))
    except Exception:
        pass

if __name__ == "__main__":
    main()
EOF

    # Compile to binary and strip
    cd /app/src
    pyinstaller --onefile migrator.py
    cp dist/migrator /app/migrator_legacy
    strip /app/migrator_legacy
    chmod +x /app/migrator_legacy

    # Cleanup source
    rm -rf /app/src

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 755 /app
