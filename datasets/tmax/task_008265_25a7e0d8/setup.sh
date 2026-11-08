#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    # Create the home directory if it doesn't exist
    mkdir -p /home/user

    # Create the manifest_emulator.py script
    cat << 'EOF' > /home/user/manifest_emulator.py
import sys
import os

def run_emulator(filepath):
    if not os.path.exists(filepath):
        sys.exit(f"Error: File not found {filepath}")

    with open(filepath, "rb") as f:
        data = f.read()

    state = "INIT"
    pc = 0
    version = 0

    while pc < len(data):
        op = data[pc]
        if state == "INIT":
            if op == 0x01:
                state = "VERSION"
                pc += 1
            else:
                sys.exit("Error: Expected INIT (0x01)")
        elif state == "VERSION":
            if op == 0x02:
                if pc + 1 >= len(data): sys.exit("Error: Missing version byte")
                version = data[pc+1]
                state = "CHECKSUM"
                pc += 2
            else:
                sys.exit("Error: Expected VERSION (0x02)")
        elif state == "CHECKSUM":
            if op == 0x03:
                if pc + 1 >= len(data): sys.exit("Error: Missing checksum byte")
                expected_csum = data[pc+1]

                # Checksum is XOR of all previous bytes
                actual_csum = 0
                for b in data[:pc]:
                    actual_csum ^= b

                if actual_csum != expected_csum:
                    sys.exit(f"Error: Checksum mismatch. Expected {expected_csum}, got {actual_csum}")
                state = "DONE"
                pc += 2
            else:
                sys.exit("Error: Expected CHECKSUM (0x03)")
        elif state == "DONE":
            break

    if state == "DONE":
        print(f"SUCCESS: Valid manifest version {version}")
        with open("/home/user/result.log", "w") as out:
            out.write(f"VALID_{version}\n")
    else:
        sys.exit("Error: Incomplete manifest. State machine did not reach DONE.")

if __name__ == "__main__":
    if len(sys.argv) < 2:
        sys.exit("Usage: python3 manifest_emulator.py <file>")
    run_emulator(sys.argv[1])
EOF

    # Create user and set permissions
    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
