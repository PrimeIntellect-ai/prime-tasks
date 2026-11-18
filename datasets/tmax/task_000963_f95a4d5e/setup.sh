#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest pexpect

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/backup_data.json
{
  "users": [
    {"username": "bwayne", "group": "wheel"},
    {"username": "ckent", "group": "reporters"}
  ],
  "interfaces": {
    "eth0": "10.100.0.5/24",
    "eth1": "172.16.55.1/20",
    "tun0": "10.8.0.1/32"
  },
  "routes": [
    {"dest": "0.0.0.0/0", "gw": "10.100.0.1"},
    {"dest": "192.168.50.0/24", "gw": "172.16.55.254"}
  ]
}
EOF

    cat << 'EOF' > /home/user/mock_router.py
import sys
import json
import os

STATE_FILE = '/home/user/.router_state'

def load_state():
    if os.path.exists(STATE_FILE):
        with open(STATE_FILE, 'r') as f:
            return json.load(f)
    return {"users": {}, "interfaces": {}, "routes": {}}

def save_state(state):
    with open(STATE_FILE, 'w') as f:
        json.dump(state, f)

def main():
    state = load_state()
    logged_in = False

    while True:
        try:
            sys.stdout.write("Router> ")
            sys.stdout.flush()
            cmd_line = sys.stdin.readline()
            if not cmd_line:
                break
            cmd_line = cmd_line.strip()
            if not cmd_line:
                continue

            parts = cmd_line.split()
            cmd = parts[0]

            if cmd == "login":
                if len(parts) == 3 and parts[1] == "admin" and parts[2] == "admin":
                    logged_in = True
                    print("Login successful.")
                else:
                    print("Error: Invalid credentials.")
            elif cmd == "exit":
                save_state(state)
                break
            elif not logged_in:
                print("Error: Please login first.")
            elif cmd == "user" and parts[1] == "add" and len(parts) == 4:
                state["users"][parts[2]] = parts[3]
                print(f"OK: User {parts[2]} added to {parts[3]}.")
            elif cmd == "interface" and parts[1] == "set" and len(parts) == 4:
                state["interfaces"][parts[2]] = parts[3]
                print(f"OK: Interface {parts[2]} set.")
            elif cmd == "route" and parts[1] == "add" and len(parts) == 4:
                state["routes"][parts[2]] = parts[3]
                print(f"OK: Route {parts[2]} added.")
            elif cmd == "dump":
                print(json.dumps(state))
            else:
                print("Error: Unknown or malformed command.")
        except EOFError:
            break

if __name__ == "__main__":
    main()
EOF

    chmod -R 777 /home/user
