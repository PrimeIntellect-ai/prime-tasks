#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest pexpect

    mkdir -p /home/user/device_configs

    cat << 'EOF' > /home/user/device_inventory.csv
node-alpha,tk_9912a,EU,y
node-beta,tk_8821b,US,n
node-gamma,tk_7734c,AP,y
EOF

    cat << 'EOF' > /home/user/iot_setup_cli
#!/usr/bin/env python3
import sys
import json
import os

def main():
    print("IoT Edge Configuration Utility v1.0")
    try:
        dev_id = input("Device ID: ").strip()
        token = input("Authentication Token: ").strip()
        region = input("Target Region (US/EU/AP): ").strip()
        telemetry = input("Enable telemetry stream? (y/n): ").strip().lower()
        commit = input("Commit configuration? (yes/no): ").strip().lower()

        if commit == 'yes':
            config = {
                "device_id": dev_id,
                "auth_token": token,
                "region": region,
                "telemetry": True if telemetry == 'y' else False
            }
            filepath = f"/home/user/device_configs/{dev_id}_active.json"
            with open(filepath, 'w') as f:
                json.dump(config, f)
            print(f"Success! Configuration saved to {filepath}")
        else:
            print("Aborted.")
    except EOFError:
        print("\nError: Unexpected EOF.")
        sys.exit(1)

if __name__ == "__main__":
    main()
EOF

    chmod +x /home/user/iot_setup_cli

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
