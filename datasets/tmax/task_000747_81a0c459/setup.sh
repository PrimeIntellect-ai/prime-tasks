#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip jq
    pip3 install pytest

    mkdir -p /home/user

    # Create the input telemetry file
    cat << 'EOF' > /home/user/telemetry.json
{
  "event": "login",
  "payload": "B64:eyAibmVzdGVkIjogIkhFWDo0ODY1NmM2YzZmIiB9",
  "metadata": "B64:bm90X2pzb25fc3RyaW5n",
  "status": "HEX:73756363657373"
}
EOF

    # Create the buggy python script
    cat << 'EOF' > /home/user/process.py
import json
import base64

def normalize_telemetry(data):
    if isinstance(data, dict):
        for k, v in data.items():
            data[k] = normalize_telemetry(v)
        return data
    elif isinstance(data, list):
        for i in range(len(data)):
            data[i] = normalize_telemetry(data[i])
        return data
    elif isinstance(data, str):
        if data.startswith("B64:"):
            encoded_part = data[4:]
            decoded_bytes = base64.b64decode(encoded_part)
            decoded_str = decoded_bytes.decode('utf-8', errors='replace')
            try:
                # Try to recursively decode if it's a nested JSON string
                nested = json.loads(decoded_str)
                return normalize_telemetry(nested)
            except json.JSONDecodeError:
                # BUG 1: Infinite recursion here instead of returning decoded_str
                return normalize_telemetry(data)
        elif data.startswith("HEX:"):
            encoded_part = data[4:]
            # BUG 2: Returns bytes object, which causes JSON serialization to fail
            return bytes.fromhex(encoded_part)
    return data

if __name__ == "__main__":
    with open("/home/user/telemetry.json", "r") as f:
        raw_data = json.load(f)

    processed = normalize_telemetry(raw_data)

    with open("/home/user/processed.json", "w") as f:
        json.dump(processed, f, indent=2)
EOF

    chmod +x /home/user/process.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
