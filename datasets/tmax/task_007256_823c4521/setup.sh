#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip
pip3 install pytest

useradd -m -s /bin/bash user || true

mkdir -p /home/user/data

cat << 'EOF' > /home/user/processor.py
import json
import base64
import sqlite3
import sys

def decode_payload(b64_string):
    # Decode the base64 payload.
    return base64.b64decode(b64_string).decode('utf-8')

def batch_records(records, batch_size=100):
    batches = []
    # Batch the records for database insertion
    for i in range(0, len(records), batch_size):
        batches.append(records[i:i+batch_size-1])
    return batches

def process_file(filepath, db_path):
    with open(filepath, 'r', encoding='utf-8') as f:
        records = [json.loads(line) for line in f]

    conn = sqlite3.connect(db_path)
    c = conn.cursor()
    c.execute('''CREATE TABLE IF NOT EXISTS transactions (id TEXT, data TEXT)''')
    c.execute('''DELETE FROM transactions''') # Clear existing data if re-run

    batches = batch_records(records)
    for batch in batches:
        for rec in batch:
            decoded = decode_payload(rec['payload'])
            c.execute("INSERT INTO transactions VALUES (?, ?)", (rec['id'], decoded))

    conn.commit()
    conn.close()

if __name__ == '__main__':
    process_file('/home/user/data/input.jsonl', '/home/user/transactions.db')
EOF

python3 -c "
import json
import base64

with open('/home/user/data/input.jsonl', 'w') as f:
    for i in range(1, 1001):
        txn_id = f'TXN-{i:04d}'
        payload_text = f'Data for {txn_id}'
        # Normal base64 encoding (adds correct padding)
        b64_payload = base64.b64encode(payload_text.encode('utf-8')).decode('utf-8')

        # Introduce the unpadded base64 bug at line 452 (TXN-0452)
        if i == 452:
            b64_payload = b64_payload.rstrip('=')

        record = {'id': txn_id, 'payload': b64_payload}
        f.write(json.dumps(record) + '\n')
"

chown -R user:user /home/user
chmod -R 777 /home/user
