#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import json
import os
import subprocess
import re
import sqlite3
import struct

def get_git_key():
    try:
        out = subprocess.check_output(
            ['git', 'log', '-p', '--all', '--', 'secret.conf'],
            cwd='/home/user/analyzer_repo',
            stderr=subprocess.DEVNULL
        ).decode('utf-8', errors='ignore')
        m = re.search(r'^\+DB_DECRYPTION_KEY=(.+)$', out, re.MULTILINE)
        if m:
            return m.group(1).strip()
    except Exception:
        pass
    return None

def get_db_token(key):
    try:
        conn = sqlite3.connect('/home/user/db/state.db')
        cur = conn.cursor()
        cur.execute("SELECT backup_token FROM recovery LIMIT 1")
        row = cur.fetchone()
        conn.close()
        if not row:
            return None
        enc_hex = row[0]
        enc_bytes = bytes.fromhex(enc_hex)
        key_bytes = key.encode('utf-8')
        dec = bytearray()
        for i in range(len(enc_bytes)):
            dec.append(enc_bytes[i] ^ key_bytes[i % len(key_bytes)])
        return dec.decode('utf-8')
    except Exception:
        return None

def get_crashing_frame():
    pcap_path = '/home/user/data/traffic.pcap'
    if not os.path.exists(pcap_path):
        return None
    try:
        with open(pcap_path, 'rb') as f:
            global_header = f.read(24)
            if len(global_header) < 24:
                return None
            magic = global_header[:4]
            if magic in (b'\xd4\xc3\xb2\xa1', b'\x4d\x3c\xb2\xa1'):
                endian = '<'
            elif magic in (b'\xa1\xb2\xc3\xd4', b'\xa1\xb2\x3c\x4d'):
                endian = '>'
            else:
                endian = '='

            frame_num = 1
            while True:
                pkt_header = f.read(16)
                if len(pkt_header) < 16:
                    break
                _, _, incl_len, _ = struct.unpack(endian + 'IIII', pkt_header)
                if incl_len == 119:
                    return frame_num
                f.seek(incl_len, 1)
                frame_num += 1
    except Exception:
        pass
    return None

def test_ticket_resolution_json():
    res_file = '/home/user/ticket_resolution.json'
    assert os.path.isfile(res_file), f"The deliverable file {res_file} is missing."

    with open(res_file, 'r') as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            assert False, f"The file {res_file} does not contain valid JSON."

    expected_key = get_git_key()
    assert expected_key is not None, "Could not determine the expected decryption key from the Git repository."

    expected_token = get_db_token(expected_key)
    assert expected_token is not None, "Could not compute the expected decrypted token from the database."

    expected_frame = get_crashing_frame()
    assert expected_frame is not None, "Could not determine the expected crashing frame from the PCAP file."

    assert "decryption_key" in data, "The key 'decryption_key' is missing from the JSON file."
    assert data["decryption_key"] == expected_key, f"Incorrect decryption_key. Expected the key found in git history."

    assert "decrypted_backup_token" in data, "The key 'decrypted_backup_token' is missing from the JSON file."
    assert data["decrypted_backup_token"] == expected_token, f"Incorrect decrypted_backup_token. Expected the XOR-decrypted token."

    assert "crashing_frame_number" in data, "The key 'crashing_frame_number' is missing from the JSON file."
    assert data["crashing_frame_number"] == expected_frame, f"Incorrect crashing_frame_number. Expected the 1-based frame number of the 119-byte packet."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
