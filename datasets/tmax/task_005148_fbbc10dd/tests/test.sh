#!/bin/bash
set -u
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import json
import pytest

REPORT_PATH = "/home/user/report.json"

def test_report_file_exists():
    assert os.path.isfile(REPORT_PATH), f"Report file {REPORT_PATH} is missing."

def test_report_is_valid_json():
    with open(REPORT_PATH, "r") as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError as e:
            pytest.fail(f"Report file {REPORT_PATH} is not valid JSON: {e}")
    assert isinstance(data, dict), "The root of the JSON report must be an object (dictionary)."

def test_report_contents():
    with open(REPORT_PATH, "r") as f:
        data = json.load(f)

    assert "invalid.bak" not in data, "invalid.bak should not be included in the report because of invalid magic bytes."

    expected_files = ["safe1.bak", "malicious_abs.bak", "malicious_rel.bak"]
    for filename in expected_files:
        assert filename in data, f"{filename} is missing from the JSON report."

    safe1 = data["safe1.bak"]
    assert safe1.get("total_entries") == 2, f"safe1.bak total_entries should be 2, got {safe1.get('total_entries')}"
    assert isinstance(safe1.get("dangerous_paths"), list), "safe1.bak dangerous_paths must be a list"
    assert len(safe1["dangerous_paths"]) == 0, f"safe1.bak should have no dangerous paths, got {safe1['dangerous_paths']}"

    mal_abs = data["malicious_abs.bak"]
    assert mal_abs.get("total_entries") == 3, f"malicious_abs.bak total_entries should be 3, got {mal_abs.get('total_entries')}"
    expected_abs_paths = {"/etc/shadow", "/root/.ssh/authorized_keys"}
    actual_abs_paths = set(mal_abs.get("dangerous_paths", []))
    assert actual_abs_paths == expected_abs_paths, f"malicious_abs.bak dangerous paths mismatch. Expected {expected_abs_paths}, got {actual_abs_paths}"

    mal_rel = data["malicious_rel.bak"]
    assert mal_rel.get("total_entries") == 3, f"malicious_rel.bak total_entries should be 3, got {mal_rel.get('total_entries')}"
    expected_rel_paths = {"../../.bashrc", "folder/../../usr/bin/python"}
    actual_rel_paths = set(mal_rel.get("dangerous_paths", []))
    assert actual_rel_paths == expected_rel_paths, f"malicious_rel.bak dangerous paths mismatch. Expected {expected_rel_paths}, got {actual_rel_paths}"
TEST_EOF

passed=1
if ! python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    passed=0
fi

run_dynamic_test() {
    local saved="/tmp/verifier_original_backups_$$"
    local generated="/home/user/backups"
    local restored=0

    restore_backups() {
        if [ "$restored" -eq 0 ]; then
            rm -rf "$generated"
            if [ -d "$saved" ]; then
                mv "$saved" "$generated"
            fi
            restored=1
        fi
    }

    mapfile -d '' sources < <(find /home/user /root /tmp -type f \( -name '*.cpp' -o -name '*.cc' -o -name '*.cxx' \) -print0 2>/dev/null)
    if [ "${#sources[@]}" -eq 0 ]; then
        echo "No C++ source file was found." >&2
        return 1
    fi

    local candidates=()
    local i=0
    local src out
    for src in "${sources[@]}"; do
        out="/tmp/verifier_candidate_${$}_${i}"
        if g++ -std=c++17 -O2 "$src" -o "$out" >/dev/null 2>&1; then
            candidates+=("$out")
        fi
        i=$((i + 1))
    done

    while IFS= read -r -d '' out; do
        candidates+=("$out")
    done < <(python3 - << 'PY'
import os
for root in ('/home/user', '/root'):
    for base, dirs, files in os.walk(root):
        for name in files:
            path = os.path.join(base, name)
            try:
                if os.access(path, os.X_OK):
                    with open(path, 'rb') as f:
                        if f.read(4) == b'\x7fELF':
                            print(path, end='\0')
            except OSError:
                pass
PY
)

    if [ "${#candidates[@]}" -eq 0 ]; then
        echo "No compilable C++ source or executable C++ artifact was found." >&2
        return 1
    fi

    mv "$generated" "$saved"
    mkdir -p "$generated"
    trap restore_backups RETURN

    python3 - << 'PY'
import os
import secrets
import struct

root = '/home/user/backups'
tag = secrets.token_hex(8)

def create(name, entries):
    with open(os.path.join(root, name), 'wb') as f:
        f.write(b'BAK1')
        f.write(struct.pack('<I', len(entries)))
        for path, payload in entries:
            encoded = path.encode('ascii')
            f.write(struct.pack('<H', len(encoded)))
            f.write(encoded)
            f.write(struct.pack('<I', len(payload)))
            f.write(payload)

create('alpha_' + tag + '.bak', [
    ('notes/' + tag + '.txt', b'BAK1\x02\x00\x00\x00'),
    ('../escape_' + tag, b'x' * 19),
    ('nested/../target_' + tag, b'payload'),
    ('dots..but_safe/' + tag, b''),
])
create('beta_' + tag + '.bak', [
    ('/absolute/' + tag, b'one'),
    ('ordinary/file.bin', b'\x00\x01\x02\xff'),
])
create('empty_' + tag + '.bak', [])

with open(os.path.join(root, 'wrong_' + tag + '.bak'), 'wb') as f:
    f.write(b'NOPE' + struct.pack('<I', 0))
with open(os.path.join(root, 'truncated_' + tag + '.bak'), 'wb') as f:
    f.write(b'BAK1' + struct.pack('<I', 2) + struct.pack('<H', 100) + b'short')
PY

    cat << 'PY' > /tmp/check_dynamic_report.py
import json
import os
import struct
import sys

root = '/home/user/backups'
expected = {}
invalid_magic = set()

for name in os.listdir(root):
    if not name.endswith('.bak'):
        continue
    raw = open(os.path.join(root, name), 'rb').read()
    if len(raw) < 8 or raw[:4] != b'BAK1':
        invalid_magic.add(name)
        continue
    count = struct.unpack_from('<I', raw, 4)[0]
    offset = 8
    paths = []
    complete = True
    for _ in range(count):
        if offset + 2 > len(raw):
            complete = False
            break
        length = struct.unpack_from('<H', raw, offset)[0]
        offset += 2
        if offset + length + 4 > len(raw):
            complete = False
            break
        path_bytes = raw[offset:offset + length]
        offset += length
        size = struct.unpack_from('<I', raw, offset)[0]
        offset += 4
        if offset + size > len(raw):
            complete = False
            break
        offset += size
        paths.append(path_bytes.decode('ascii'))
    if complete:
        expected[name] = {
            'total_entries': count,
            'dangerous_paths': [p for p in paths if p.startswith('/') or '../' in p],
        }

try:
    with open('/home/user/report.json', 'r') as f:
        report = json.load(f)
except Exception as exc:
    print('Dynamic report is missing or invalid:', exc, file=sys.stderr)
    sys.exit(1)

if not isinstance(report, dict):
    sys.exit(1)
for name in invalid_magic:
    if name in report:
        print('Invalid-magic archive was included:', name, file=sys.stderr)
        sys.exit(1)
for name, wanted in expected.items():
    if name not in report or not isinstance(report[name], dict):
        print('Generated archive is missing:', name, file=sys.stderr)
        sys.exit(1)
    got = report[name]
    if got.get('total_entries') != wanted['total_entries']:
        print('Wrong entry count for', name, file=sys.stderr)
        sys.exit(1)
    dangerous = got.get('dangerous_paths')
    if not isinstance(dangerous, list) or sorted(dangerous) != sorted(wanted['dangerous_paths']):
        print('Wrong dangerous paths for', name, file=sys.stderr)
        sys.exit(1)
PY

    local candidate
    for candidate in "${candidates[@]}"; do
        rm -f /home/user/report.json
        if (cd /home/user && timeout 10s "$candidate" >/dev/null 2>&1) && python3 /tmp/check_dynamic_report.py; then
            restore_backups
            trap - RETURN
            return 0
        fi
    done

    echo "No C++ artifact produced the correct report for generated archives." >&2
    restore_backups
    trap - RETURN
    return 1
}

if [ "$passed" -eq 1 ]; then
    if ! run_dynamic_test; then
        passed=0
    fi
fi

if [ "$passed" -eq 1 ]; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
