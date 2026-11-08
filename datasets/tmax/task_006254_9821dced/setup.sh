#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    mkdir -p /home/user

    # Create the Python script with no error handling
    cat << 'EOF' > /home/user/parser.py
import json

def process_logs(input_file, output_file):
    with open(input_file, 'r') as f_in, open(output_file, 'w') as f_out:
        for line in f_in:
            data = json.loads(line.strip())
            user_id = data['event']['user']['id']
            f_out.write(f"{user_id}\n")

if __name__ == '__main__':
    process_logs('/home/user/incoming_logs.txt', '/home/user/extracted_users.txt')
EOF

    # Create the data file with edge cases (KeyError and JSONDecodeError triggers)
    cat << 'EOF' > /home/user/incoming_logs.txt
{"event": {"user": {"id": "U1001", "role": "admin"}}}
{"event": {"user": {"id": "U1002", "role": "user"}}}
{"event": {"user": {"name": "Alice_No_ID"}}}
{"event": {"user": {"id": "U1003", "role": "user"}}}
{"event": "corrupted_payload_missing_braces"
{"event": {"user": {"id": "U1004", "role": "guest"}}}
EOF

    # Create the traceback log simulating the crash on the 3rd line
    cat << 'EOF' > /home/user/crash_traceback.log
Traceback (most recent call last):
  File "/home/user/parser.py", line 11, in <module>
    process_logs('/home/user/incoming_logs.txt', '/home/user/extracted_users.txt')
  File "/home/user/parser.py", line 7, in process_logs
    user_id = data['event']['user']['id']
KeyError: 'id'
EOF

    chmod +x /home/user/parser.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
