#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip curl gcc make espeak
    pip3 install pytest

    mkdir -p /app
    espeak -w /app/update.wav "Please update the system. The new API version is 4, and the transformation offset is 12."

    mkdir -p /home/user/c_module
    cat << 'EOF' > /home/user/c_module/data_processor.c
void process_data(char* data, int offset) {
    while(*data) {
        if (*data >= 'A' && *data <= 'Z') {
            *data = 'A' + (*data - 'A' + offset) % 26;
        } else if (*data >= 'a' && *data <= 'z') {
            *data = 'a' + (*data - 'a' + offset) % 26;
        }
        data++;
    }
}
EOF

    cat << 'EOF' > /home/user/c_module/Makefile
libprocessor.so: data_processor.c
	gcc data_processor.c -o libprocessor.so
EOF

    cat << 'EOF' > /app/reference_oracle
#!/usr/bin/env python3
import sys
import json

def process_data(data, offset):
    result = []
    for char in data:
        if 'A' <= char <= 'Z':
            result.append(chr(ord('A') + (ord(char) - ord('A') + offset) % 26))
        elif 'a' <= char <= 'z':
            result.append(chr(ord('a') + (ord(char) - ord('a') + offset) % 26))
        else:
            result.append(char)
    return "".join(result)

def main():
    if len(sys.argv) != 2:
        print(json.dumps({"status": "error"}))
        return
    try:
        data = json.loads(sys.argv[1])
        if data.get("endpoint") == "/api/v4/process" and "payload" in data:
            res = process_data(data["payload"], 12)
            print(json.dumps({"status": "success", "result": res}))
        else:
            print(json.dumps({"status": "error"}))
    except Exception:
        print(json.dumps({"status": "error"}))

if __name__ == "__main__":
    main()
EOF
    chmod +x /app/reference_oracle

    # Install Rust
    curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user /app
