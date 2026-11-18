#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/app_logs.jsonl
{"timestamp": 1700000000.1234567890123456789, "payload": {"inner": {"inner": {"data": "critical_event_1"}}}, "encoded_msg": "SGVsbG8gV29ybGQ"}
{"timestamp": 1700000005.9876543210987654321, "payload": {"inner": {"data": "critical_event_2"}}, "encoded_msg": "YWdlbnQgYWN0aXZhdGVk"}
{"timestamp": 1700000010.5555555555555555555, "payload": {"data": "critical_event_3"}, "encoded_msg": "cGFkZGluZyBpc3N1ZQ"}
EOF

    cat << 'EOF' > /home/user/log_processor.py
import json
import base64

def unwrap_payload(payload):
    if isinstance(payload, dict) and 'inner' in payload:
        return unwrap_payload(payload) # BUG: should be payload['inner']
    return payload

def process_logs(input_file, output_file):
    processed = []
    with open(input_file, 'r') as f:
        for line in f:
            # BUG: json.loads without parse_float will lose precision on high-res timestamps
            entry = json.loads(line)

            if 'payload' in entry:
                entry['payload'] = unwrap_payload(entry['payload'])

            if 'encoded_msg' in entry:
                msg = entry['encoded_msg']
                # BUG: missing padding fix for base64
                entry['decoded_msg'] = base64.b64decode(msg).decode('utf-8')

            processed.append(entry)

    with open(output_file, 'w') as f:
        for p in processed:
            f.write(json.dumps(p) + '\n')

if __name__ == "__main__":
    process_logs('/home/user/app_logs.jsonl', '/home/user/processed_logs.jsonl')
EOF
    chmod +x /home/user/log_processor.py

    chmod -R 777 /home/user
