#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import json
import re
import hashlib
import pytest

def get_expected_session_id():
    log_path = "/home/user/traffic.log"
    assert os.path.isfile(log_path), f"Missing required file: {log_path}"

    with open(log_path, 'r') as f:
        content = f.read()

    blocks = re.split(r'\n\s*\n', content.strip())

    for i, block in enumerate(blocks):
        if "Content-Security-Policy" in block and "'unsafe-inline'" in block:
            if i > 0:
                req_block = blocks[i-1]
                match = re.search(r'Cookie:\s*.*Session-Id=([A-Za-z0-9_]+)', req_block)
                if match:
                    return match.group(1)
    return None

def get_expected_cn():
    cert_path = "/home/user/cert.pem"
    assert os.path.isfile(cert_path), f"Missing required file: {cert_path}"

    with open(cert_path, 'r') as f:
        content = f.read()

    match = re.search(r'Subject:.*?CN=([A-Za-z0-9_]+)', content)
    if match:
        return match.group(1)
    return None

def get_expected_pins(cn):
    hashes_path = "/home/user/hashes.txt"
    assert os.path.isfile(hashes_path), f"Missing required file: {hashes_path}"

    with open(hashes_path, 'r') as f:
        target_hashes = [line.strip() for line in f if line.strip()]

    expected_pins = []
    hash_to_pin = {}
    for i in range(10000):
        pin = f"{i:04d}"
        payload = (pin + cn).encode('utf-8')
        h = hashlib.sha256(payload).hexdigest()
        hash_to_pin[h] = pin

    for th in target_hashes:
        assert th in hash_to_pin, f"Hash {th} in hashes.txt does not correspond to a valid 4-digit PIN with salt {cn}"
        expected_pins.append(hash_to_pin[th])

    return expected_pins

def test_report_exists():
    report_path = "/home/user/report.json"
    assert os.path.isfile(report_path), f"The final report file was not found at {report_path}. Ensure your Rust program outputs to the correct absolute path."

def test_report_content():
    report_path = "/home/user/report.json"
    assert os.path.isfile(report_path), f"Report file missing: {report_path}"

    with open(report_path, 'r') as f:
        try:
            report_data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"The file {report_path} does not contain valid JSON.")

    expected_session_id = get_expected_session_id()
    assert expected_session_id is not None, "Could not derive expected session ID from traffic.log"

    expected_cn = get_expected_cn()
    assert expected_cn is not None, "Could not derive expected CN from cert.pem"

    expected_pins = get_expected_pins(expected_cn)

    assert "vulnerable_session_id" in report_data, "Report JSON is missing the 'vulnerable_session_id' key."
    assert report_data["vulnerable_session_id"] == expected_session_id, \
        f"Expected vulnerable_session_id to be {expected_session_id}, but got {report_data['vulnerable_session_id']}."

    assert "certificate_cn" in report_data, "Report JSON is missing the 'certificate_cn' key."
    assert report_data["certificate_cn"] == expected_cn, \
        f"Expected certificate_cn to be {expected_cn}, but got {report_data['certificate_cn']}."

    assert "cracked_pins" in report_data, "Report JSON is missing the 'cracked_pins' key."
    assert isinstance(report_data["cracked_pins"], list), "'cracked_pins' must be a JSON array."
    assert report_data["cracked_pins"] == expected_pins, \
        f"Expected cracked_pins to be {expected_pins}, but got {report_data['cracked_pins']}. Ensure PINs are in the same order as hashes.txt."
TEST_EOF

run_checks() {
    test -f /home/user/analyzer/Cargo.toml || return 1
    find /home/user/analyzer -type f -name '*.rs' -print -quit | grep -q . || return 1

    local metadata=/tmp/analyzer_metadata.json
    local build_log=/tmp/analyzer_build.jsonl
    local bin_name_file=/tmp/analyzer_bin_name
    local executable_file=/tmp/analyzer_executable

    env RUSTC=/usr/bin/rustc RUSTC_WRAPPER= RUSTC_WORKSPACE_WRAPPER= \
        cargo metadata --format-version=1 --no-deps --manifest-path /home/user/analyzer/Cargo.toml > "$metadata" || return 1

    python3 - "$metadata" > "$bin_name_file" << 'PY_EOF' || return 1
import json, os, sys
m = json.load(open(sys.argv[1]))
manifest = os.path.realpath('/home/user/analyzer/Cargo.toml')
packages = [p for p in m['packages'] if os.path.realpath(p['manifest_path']) == manifest]
if len(packages) != 1:
    raise SystemExit('Could not identify analyzer package')
p = packages[0]
bins = [t['name'] for t in p['targets'] if 'bin' in t['kind']]
default = p.get('default_run')
if default:
    if default not in bins:
        raise SystemExit('default-run does not name a binary target')
    print(default)
elif len(bins) == 1:
    print(bins[0])
else:
    raise SystemExit('Project has no unambiguous runnable binary')
PY_EOF

    local bin_name
    bin_name=$(cat "$bin_name_file")
    test -n "$bin_name" || return 1

    env RUSTC=/usr/bin/rustc RUSTC_WRAPPER= RUSTC_WORKSPACE_WRAPPER= \
        cargo clean --manifest-path /home/user/analyzer/Cargo.toml || return 1
    env RUSTC=/usr/bin/rustc RUSTC_WRAPPER= RUSTC_WORKSPACE_WRAPPER= \
        cargo build --manifest-path /home/user/analyzer/Cargo.toml --bin "$bin_name" --message-format=json > "$build_log" || return 1

    python3 - "$build_log" "$bin_name" > "$executable_file" << 'PY_EOF' || return 1
import json, os, sys
found = []
for line in open(sys.argv[1]):
    try:
        msg = json.loads(line)
    except json.JSONDecodeError:
        continue
    target = msg.get('target', {})
    exe = msg.get('executable')
    if msg.get('reason') == 'compiler-artifact' and exe and target.get('name') == sys.argv[2] and 'bin' in target.get('kind', []):
        found.append(exe)
if not found:
    raise SystemExit('Cargo did not produce the requested Rust binary')
exe = os.path.realpath(found[-1])
if not os.path.isfile(exe) or not os.access(exe, os.X_OK):
    raise SystemExit('Compiled binary is missing or not executable')
with open(exe, 'rb') as f:
    if f.read(4) != b'\x7fELF':
        raise SystemExit('Compiled artifact is not an ELF executable')
print(exe)
PY_EOF

    local executable
    executable=$(cat "$executable_file")
    test -n "$executable" || return 1

    rm -f /home/user/report.json
    (cd /home/user/analyzer && timeout 180 "$executable") || return 1
    python3 -m pytest /tmp/test_final_state.py -x --tb=short || return 1

    local backup
    backup=$(mktemp -d)
    cp /home/user/traffic.log "$backup/traffic.log" || return 1
    cp /home/user/cert.pem "$backup/cert.pem" || return 1
    cp /home/user/hashes.txt "$backup/hashes.txt" || return 1

    python3 << 'PY_EOF' || return 1
import hashlib
import secrets

session = 'DynamicSession_' + secrets.token_hex(8)
cn = 'Dynamic_CA_' + secrets.token_hex(8)
pins = [f'{secrets.randbelow(10000):04d}' for _ in range(2)]

with open('/home/user/traffic.log', 'w') as f:
    f.write(f'''GET /safe HTTP/1.1
Host: example.com
Cookie: Session-Id=Safe_{secrets.token_hex(4)}

HTTP/1.1 200 OK
Content-Security-Policy: default-src 'self'

GET /dynamic HTTP/1.1
Host: example.com
Cookie: theme=dark; Session-Id={session}; mode=test

HTTP/1.1 200 OK
Content-Security-Policy: default-src 'self' 'unsafe-inline'

GET /later HTTP/1.1
Host: example.com
Cookie: Session-Id=Later_{secrets.token_hex(4)}

HTTP/1.1 200 OK
Content-Security-Policy: default-src 'self' 'unsafe-inline'
''')

with open('/home/user/cert.pem', 'w') as f:
    f.write(f'''Certificate:
    Data:
        Issuer: C=US, O=DynamicIssuer, CN=Unrelated_Root
        Subject: C=US, ST=WA, O=DynamicCorp, CN={cn}
        Subject Public Key Info:
-----BEGIN CERTIFICATE-----
DYNAMICMOCK
-----END CERTIFICATE-----
''')

with open('/home/user/hashes.txt', 'w') as f:
    for pin in pins:
        f.write(hashlib.sha256((pin + cn).encode()).hexdigest() + '\n')
PY_EOF

    rm -f /home/user/report.json
    (cd /home/user/analyzer && timeout 180 "$executable") || return 1
    python3 -m pytest /tmp/test_final_state.py -x --tb=short || return 1

    cp "$backup/traffic.log" /home/user/traffic.log
    cp "$backup/cert.pem" /home/user/cert.pem
    cp "$backup/hashes.txt" /home/user/hashes.txt
    rm -rf "$backup"
    return 0
}

if run_checks 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
