#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip binutils
    pip3 install pytest pyinstaller

    # Create the python script for the sys-profiler
    cat << 'EOF' > /tmp/sys-profiler.py
import argparse
import socket
import json
import os
import glob

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--data-dir', required=True)
    parser.add_argument('--tcp-port', type=int, required=True)
    args = parser.parse_args()

    server = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    server.bind(('127.0.0.1', args.tcp_port))
    server.listen(5)

    while True:
        try:
            conn, addr = server.accept()
            data = conn.recv(1024).decode()
            if data == "GENERATE_PLAN\n":
                total_cpu = 0
                total_mem = 0
                if os.path.exists(args.data_dir):
                    for f in glob.glob(os.path.join(args.data_dir, '*.json')):
                        try:
                            with open(f) as fp:
                                d = json.load(fp)
                                total_cpu += d.get('cpu', 0)
                                total_mem += d.get('mem', 0)
                        except Exception:
                            pass
                resp = json.dumps({"status": "ok", "total_cpu": total_cpu, "total_mem": total_mem}) + "\n"
                conn.sendall(resp.encode())
            conn.close()
        except Exception:
            pass

if __name__ == '__main__':
    main()
EOF

    # Compile the python script into a binary
    cd /tmp
    pyinstaller --onefile sys-profiler.py

    mkdir -p /app/bin
    cp dist/sys-profiler /app/bin/sys-profiler
    chmod +x /app/bin/sys-profiler
    strip /app/bin/sys-profiler || true

    # Cleanup
    rm -rf /tmp/build /tmp/dist /tmp/sys-profiler.py /tmp/sys-profiler.spec

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
