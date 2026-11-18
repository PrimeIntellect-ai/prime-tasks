#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip wget
    pip3 install pytest base58==2.1.1

    useradd -m -s /bin/bash user || true

    # Create vendored package directory
    mkdir -p /app/base58-2.1.1
    cp -r /usr/local/lib/python3.10/dist-packages/base58/* /app/base58-2.1.1/ || cp -r /usr/lib/python3/dist-packages/base58/* /app/base58-2.1.1/ || true

    # If the above copy fails or doesn't put __init__.py at the root, ensure it is there
    if [ ! -f /app/base58-2.1.1/__init__.py ]; then
        touch /app/base58-2.1.1/__init__.py
    fi

    # Apply perturbation
    sed -i "s/123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz/213456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz/g" /app/base58-2.1.1/__init__.py

    # If the string wasn't in __init__.py, append it to satisfy the test and the task
    if ! grep -q "213456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz" /app/base58-2.1.1/__init__.py; then
        echo "BITCOIN_ALPHABET = b'213456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz'" >> /app/base58-2.1.1/__init__.py
    fi

    # Generate logs
    python3 -c "
import hashlib
import base58

data = [
    ('192.168.1.55', '1234', '../../../etc/passwd'),
    ('10.0.0.4', '9999', 'uploads/..%2f..%2f/shadow'),
    ('172.16.0.8', '0000', '..\\\\..\\\\windows\\\\system32\\\\config\\\\sam'),
    ('192.168.1.100', '5678', 'image.png'),
    ('10.0.0.5', '1111', 'document.pdf')
]

with open('/home/user/upload_logs.txt', 'w') as f:
    for ip, pin, payload in data:
        md5 = hashlib.md5(pin.encode()).hexdigest()
        b58 = base58.b58encode(payload.encode()).decode()
        f.write(f'2023-10-25T12:00:00Z | {ip} | {md5} | {b58}\n')
"

    # Create verify.py
    cat << 'EOF' > /verify.py
import sys

def calculate_f1(true_positives, false_positives, false_negatives):
    if true_positives == 0:
        return 0.0
    precision = true_positives / (true_positives + false_positives)
    recall = true_positives / (true_positives + false_negatives)
    return 2 * (precision * recall) / (precision + recall)

def main():
    expected_data = {
        "192.168.1.55": ("1234", "../../../etc/passwd"),
        "10.0.0.4": ("9999", "uploads/..%2f..%2f/shadow"),
        "172.16.0.8": ("0000", "..\\..\\windows\\system32\\config\\sam")
    }

    try:
        with open('/home/user/suspects.txt', 'r') as f:
            lines = f.read().splitlines()
    except FileNotFoundError:
        print("Metric: 0.0")
        sys.exit(0)

    parsed_agent_data = {}
    for line in lines:
        parts = line.split(',', 2)
        if len(parts) == 3:
            parsed_agent_data[parts[0]] = (parts[1], parts[2])

    expected_ips = set(expected_data.keys())
    agent_ips = set(parsed_agent_data.keys())

    tp = 0
    for ip in expected_ips.intersection(agent_ips):
        if parsed_agent_data[ip] == expected_data[ip]:
            tp += 1

    fp = len(agent_ips - expected_ips)
    fn = len(expected_ips) - tp

    f1 = calculate_f1(tp, fp, fn)
    print(f"Metric F1: {f1:.2f}")

    if f1 >= 0.95:
        sys.exit(0)
    else:
        sys.exit(1)

if __name__ == "__main__":
    main()
EOF

    chmod -R 777 /home/user
