#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip
pip3 install pytest

mkdir -p /home/user/app
mkdir -p /home/user/logs

cat << 'EOF' > /home/user/app/ingest.py
import os
import sys
import struct
import sqlite3
import glob

def init_db(db_path):
    conn = sqlite3.connect(db_path)
    c = conn.cursor()
    c.execute('''CREATE TABLE IF NOT EXISTS logs (timestamp INTEGER, status INTEGER, message TEXT)''')
    conn.commit()
    return conn

def process_file(filepath, conn):
    c = conn.cursor()
    with open(filepath, 'rb') as f:
        magic = f.read(4)
        if magic != b'LOGS':
            return

        count_data = f.read(2)
        if len(count_data) < 2: return
        count = struct.unpack('>H', count_data)[0]

        for _ in range(count):
            ts_data = f.read(4)
            if len(ts_data) < 4:
                raise ValueError("Unexpected EOF reading timestamp")
            ts = struct.unpack('>I', ts_data)[0]

            status_data = f.read(1)
            status = struct.unpack('B', status_data)[0]

            len_data = f.read(1)
            msg_len = struct.unpack('B', len_data)[0]

            msg_data = f.read(msg_len)
            msg = msg_data.decode('utf-8', errors='ignore')

            c.execute("INSERT INTO logs (timestamp, status, message) VALUES (?, ?, ?)", (ts, status, msg))
    conn.commit()

if __name__ == '__main__':
    db_path = '/home/user/app/logs.db'
    if os.path.exists(db_path):
        os.remove(db_path)
    conn = init_db(db_path)

    files = sorted(glob.glob('/home/user/logs/*.bin'))
    for f in files:
        try:
            process_file(f, conn)
        except Exception as e:
            print("Fatal Error: Parsing failed")
            sys.exit(1)
EOF

cat << 'EOF' > /home/user/app/generate_logs.py
import struct
import os

def write_log(filename, records):
    with open(filename, 'wb') as f:
        f.write(b'LOGS')
        f.write(struct.pack('>H', len(records)))
        for rec in records:
            ts, status, msg_len, msg = rec
            f.write(struct.pack('>I', ts))
            f.write(struct.pack('B', status))
            f.write(struct.pack('B', msg_len))
            if msg_len != 255 and msg is not None:
                f.write(msg.encode('utf-8'))

# log_01: 2 valid records (Status 1, 2)
write_log('/home/user/logs/log_01.bin', [
    (1620000000, 1, 4, "Test"),
    (1620000001, 2, 2, "Hi")
])

# log_02: 3 valid records (Status 1, 1, 0)
write_log('/home/user/logs/log_02.bin', [
    (1620000002, 1, 1, "A"),
    (1620000003, 1, 2, "BB"),
    (1620000004, 0, 3, "CCC")
])

# log_03: 1 valid (Status 2), 1 deleted (Length 255), 1 valid (Status 1)
# The bug triggers here because ingest.py reads 255 bytes for the deleted record, 
# corrupting the stream and hitting EOF on the next record.
write_log('/home/user/logs/log_03.bin', [
    (1620000005, 2, 5, "Hello"),
    (1620000006, 0, 255, None),
    (1620000007, 1, 4, "Good")
])

# log_04: 2 valid records (Status 1, 0)
write_log('/home/user/logs/log_04.bin', [
    (1620000008, 1, 2, "OK"),
    (1620000009, 0, 4, "Fail")
])

# log_05: 1 valid record (Status 1)
write_log('/home/user/logs/log_05.bin', [
    (1620000010, 1, 4, "Done")
])
EOF

python3 /home/user/app/generate_logs.py
rm /home/user/app/generate_logs.py

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
