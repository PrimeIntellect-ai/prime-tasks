#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc make wget tar sed
    pip3 install pytest

    # Download and extract cJSON
    mkdir -p /app
    cd /tmp
    wget https://github.com/DaveGamble/cJSON/archive/refs/tags/v1.7.15.tar.gz
    tar -xzf v1.7.15.tar.gz
    mv cJSON-1.7.15 /app/cJSON

    # Break the Makefile by removing the -shared flag
    sed -i 's/$(CC) -shared -o $@ $^ $(LDFLAGS)/$(CC) -o $@ $^ $(LDFLAGS)/g' /app/cJSON/Makefile

    # Create sensor_data.json
    mkdir -p /home/user
    cat << 'EOF' > /home/user/sensor_data.json
{
  "id": "root",
  "value": 10.5,
  "children": [
    {
      "id": "node1",
      "value": 50.0,
      "children": []
    },
    {
      "id": "node2",
      "value": 0.0,
      "children": [
        {"id": "node3", "value": 150.0, "children": []},
        {"id": "node4", "value": 5.0, "children": []}
      ]
    }
  ]
}
EOF

    # Create verify.py
    cat << 'EOF' > /verify.py
import sys

def verify():
    expected = {
        "node3": 150.0,
        "node2": 155.0,
        "root": 215.5
    }

    actual = {}
    try:
        with open('/home/user/results.csv', 'r') as f:
            for line in f:
                parts = line.strip().split(',')
                if len(parts) == 2:
                    actual[parts[0]] = float(parts[1])
    except FileNotFoundError:
        print("Accuracy: 0.0")
        sys.exit(1)

    correct = 0
    for k, v in expected.items():
        if k in actual and abs(actual[k] - v) < 0.01:
            correct += 1

    # Penalize false positives
    accuracy = correct / max(len(expected), len(actual))

    print(f"Accuracy: {accuracy}")
    if accuracy >= 1.0:
        sys.exit(0)
    else:
        sys.exit(1)

if __name__ == "__main__":
    verify()
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app/cJSON
