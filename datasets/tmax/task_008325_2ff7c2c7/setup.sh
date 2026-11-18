#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    # Create log file using python to ensure exact bytes
    python3 -c "
with open('/home/user/server.log', 'wb') as f:
    f.write(b'[INFO] System started normally.\n')
    f.write(b'[WARN] Missing config file.\n')
    f.write(b'[ERROR] Failed to load module \xff\n')
    f.write(b'[DEBUG] Connection from [192.168.1.1] established.\n')
    f.write(b'[INFO] User input: [unterminated string\n')
    f.write(b'[INFO] System shutting down.\n')
"

    # Create broken python script
    cat << 'EOF' > /home/user/log_parser.py
import json
import sys

def extract_tags(text):
    tags = []
    i = 0
    while i < len(text):
        if text[i] == '[':
            end = text.find(']', i)
            if end == -1:
                # Bug: Missing loop advancement causes infinite loop
                continue
            tags.append(text[i+1:end])
            i = end + 1
        else:
            i += 1
    return tags

def main():
    if len(sys.argv) != 3:
        print("Usage: python log_parser.py <input.log> <output.json>")
        return

    in_file = sys.argv[1]
    out_file = sys.argv[2]

    parsed_data = []

    with open(in_file, 'rb') as f:
        for line_num, line in enumerate(f, 1):
            # Bug: Fails on non-UTF-8 bytes
            decoded = line.decode('utf-8')
            tags = extract_tags(decoded)
            parsed_data.append({
                "line": line_num,
                "tags": tags,
                "raw": decoded.strip()
            })

    with open(out_file, 'w') as f:
        json.dump(parsed_data, f, indent=2)

if __name__ == "__main__":
    main()
EOF

    chmod +x /home/user/log_parser.py
    chmod -R 777 /home/user
