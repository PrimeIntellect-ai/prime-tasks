#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os

def test_payload_exists():
    assert os.path.isfile('/home/user/payload.bin'), "The file /home/user/payload.bin does not exist. Ensure you saved your raw payload exactly to this path."

def test_payload_bypasses_waf():
    with open('/home/user/payload.bin', 'rb') as f:
        payload_bytes = f.read()

    assert b'flag' not in payload_bytes, "WAF Bypass Failed: Payload contains the blocked string 'flag'."
    assert b'user' not in payload_bytes, "WAF Bypass Failed: Payload contains the blocked string 'user'."
    assert b'../' not in payload_bytes, "WAF Bypass Failed: Payload contains the blocked directory traversal string '../'."
    assert b'..\\' not in payload_bytes, "WAF Bypass Failed: Payload contains the blocked directory traversal string '..\\'."

def test_payload_decodes_to_target():
    with open('/home/user/payload.bin', 'rb') as f:
        payload_bytes = f.read()

    try:
        decoded_path = payload_bytes.decode('unicode_escape')
    except Exception as e:
        assert False, f"Payload decoding error: {e}. The payload must be valid for 'unicode_escape' decoding."

    assert decoded_path == '/home/user/flag.txt', f"The decoded payload does not evaluate to the target file path. Expected '/home/user/flag.txt', got '{decoded_path}'."

def test_exfiltrated_file_exists():
    assert os.path.isfile('/home/user/exfiltrated.txt'), "The file /home/user/exfiltrated.txt does not exist. Ensure you ran the server script with your payload to exfiltrate the data."

def test_exfiltrated_data_matches_flag():
    with open('/home/user/flag.txt', 'r') as f:
        expected_content = f.read()

    with open('/home/user/exfiltrated.txt', 'r') as f:
        actual_content = f.read()

    assert actual_content == expected_content, "The content of /home/user/exfiltrated.txt does not match the content of /home/user/flag.txt."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
