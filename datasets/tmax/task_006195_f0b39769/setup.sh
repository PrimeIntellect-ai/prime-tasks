#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    mkdir -p /home/user
    cat << 'EOF' > /home/user/mock_qemu.py
#!/usr/bin/env python3
import time
import sys

def main():
    print("[INFO] Booting VM...", flush=True)
    time.sleep(1)
    print("[INFO] Loading drivers...", flush=True)
    time.sleep(1)
    print("[INFO] VNC server running on 127.0.0.1:5900", flush=True)

    try:
        cmd = sys.stdin.readline().strip()
        if cmd == "MIGRATE":
            time.sleep(0.5)
            print("[SUCCESS] VM state exported", flush=True)
            sys.exit(0)
        else:
            print(f"[ERROR] Unknown command: {cmd}", flush=True)
            sys.exit(1)
    except KeyboardInterrupt:
        sys.exit(1)

if __name__ == "__main__":
    main()
EOF
    chmod +x /home/user/mock_qemu.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
