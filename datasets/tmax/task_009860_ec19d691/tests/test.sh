#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import stat
import base64
import urllib.parse
import pytest

def test_attacker_ip_extracted():
    path = "/home/user/attacker_ip.txt"
    assert os.path.isfile(path), f"File {path} does not exist."
    with open(path, "r") as f:
        content = f.read().strip()
    assert content == "192.168.1.105", f"Expected attacker IP '192.168.1.105', but found '{content}'."

def test_decoded_payload():
    path = "/home/user/decoded_payload.sh"
    assert os.path.isfile(path), f"File {path} does not exist."

    # The expected payload is derived from the base64 string in the log
    b64_payload = "Y2htb2QgNzc3IC9ob21lL3VzZXIvY29uZmlnLyo7IGVjaG8gIjw/cGhwIHN5c3RlbSgkeyNfR0VUWydjbWQnXX0pOyA/PiIgPiAvaG9tZS91c2VyL2NvbmZpZy9iYWNrZG9vci5waHA="
    expected_decoded = base64.b64decode(b64_payload).decode('utf-8')

    with open(path, "r") as f:
        content = f.read().strip()

    assert content == expected_decoded.strip(), "The decoded payload in decoded_payload.sh does not match the exact decoded base64 string."

def test_backdoor_removed():
    path = "/home/user/config/backdoor.php"
    assert not os.path.exists(path), f"The backdoor file {path} should have been deleted."

def test_file_permissions_restored():
    files = [
        "/home/user/config/database.conf",
        "/home/user/config/settings.ini"
    ]
    for f in files:
        assert os.path.exists(f), f"File {f} is missing."
        st = os.stat(f)
        mode = stat.S_IMODE(st.st_mode)
        assert mode == 0o644, f"File {f} must have 644 permissions, got {oct(mode)}."

def test_directory_permissions_restored():
    path = "/home/user/config/sub_dir"
    assert os.path.isdir(path), f"Directory {path} is missing."
    st = os.stat(path)
    mode = stat.S_IMODE(st.st_mode)
    assert mode == 0o755, f"Directory {path} must have 755 permissions, got {oct(mode)}."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
