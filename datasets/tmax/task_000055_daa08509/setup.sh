#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest pexpect

    mkdir -p /home/user/device_data

    cat << 'EOF' > /home/user/mock_service.py
import socket
import time
import sys

def run_service():
    server = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    server.bind(('127.0.0.1', 9090))
    server.listen(1)
    while True:
        try:
            conn, addr = server.accept()
            conn.close()
        except KeyboardInterrupt:
            break

if __name__ == '__main__':
    run_service()
EOF

    cat << 'EOF' > /home/user/interactive_cli.py
import sys
import time

def log_action(action):
    with open('/home/user/cli_backend.log', 'a') as f:
        f.write(action + '\n')

def main():
    sys.stdout.write('Enter Edge ID: ')
    sys.stdout.flush()
    edge_id = sys.stdin.readline().strip()

    sys.stdout.write('Enter Passcode: ')
    sys.stdout.flush()
    passcode = sys.stdin.readline().strip()

    if edge_id != 'EDGE-999' or passcode != '314159':
        print("Authentication failed.")
        sys.exit(1)

    log_action("AUTH_SUCCESS")

    while True:
        sys.stdout.write('edge-shell> ')
        sys.stdout.flush()
        cmd = sys.stdin.readline().strip()

        if cmd == 'exit':
            log_action("EXITED")
            break
        elif cmd.startswith('stop '):
            container = cmd.split(' ')[1]
            log_action(f"STOPPED:{container}")
            print(f"Container {container} stopped.")
        elif cmd.startswith('start '):
            container = cmd.split(' ')[1]
            log_action(f"STARTED:{container}")
            print(f"Container {container} started.")
        else:
            print("Unknown command.")

if __name__ == '__main__':
    main()
EOF

    chmod +x /home/user/interactive_cli.py
    rm -f /home/user/edge_status.log
    rm -f /home/user/cli_backend.log

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
