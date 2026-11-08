#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/router_cli
#!/usr/bin/env python3
import sys

def main():
    sys.stdout.write("Password: ")
    sys.stdout.flush()
    pw = sys.stdin.readline().strip()
    if pw != "adminpass":
        print("Access denied")
        return

    state = "normal"
    configured = False
    while True:
        if state == "normal":
            sys.stdout.write("Router> ")
        elif state == "enable":
            sys.stdout.write("Router# ")
        elif state == "config":
            sys.stdout.write("Router(config)# ")
        elif state == "config-if":
            sys.stdout.write("Router(config-if)# ")

        sys.stdout.flush()
        cmd = sys.stdin.readline()
        if not cmd:
            break
        cmd = cmd.strip()

        if cmd == "enable" and state == "normal":
            state = "enable"
        elif cmd == "configure terminal" and state == "enable":
            state = "config"
        elif cmd == "interface tun0" and state == "config":
            state = "config-if"
        elif cmd == "ip address 10.0.0.1 255.255.255.0" and state == "config-if":
            configured = True
        elif cmd == "exit":
            if state == "config-if":
                state = "config"
            elif state == "config":
                state = "enable"
            elif state == "enable":
                state = "normal"
            else:
                break
        elif cmd == "show interface tun0 metrics" and state in ("normal", "enable"):
            if not configured:
                print("Interface tun0 is not configured.")
            else:
                print("Interface tun0:")
                print(" Rx_Bytes: 154321")
                print(" Tx_Bytes: 89432")
                print(" Drops: 12")
        elif cmd == "quit":
            break
        elif cmd != "":
            print(f"Unknown command: {cmd}")

if __name__ == "__main__":
    main()
EOF

    chmod +x /home/user/router_cli
    chmod -R 777 /home/user
