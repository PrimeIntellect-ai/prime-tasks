#!/bin/bash
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import json
import stat
import pytest

def test_firewall_policy_log():
    log_path = '/home/user/firewall_policy.log'
    assert os.path.isfile(log_path), f"Log file {log_path} is missing."

    with open(log_path, 'r') as f:
        lines = [line.strip() for line in f.readlines() if line.strip()]

    expected_lines = {
        "BLOCK /home/user/intercepted/payload_01.dat",
        "ALLOW /home/user/intercepted/payload_02.dat",
        "BLOCK /home/user/intercepted/payload_03.dat"
    }

    actual_lines = set(lines)
    assert actual_lines == expected_lines, f"Firewall policy log contents are incorrect. Expected {expected_lines}, got {actual_lines}"

def test_safe_token_file():
    token_path = '/home/user/safe_token.txt'
    assert os.path.isfile(token_path), f"Token file {token_path} is missing."

    with open(token_path, 'r') as f:
        content = f.read().strip()

    assert content == "X9f2M4pL1vQ8z", f"Token file contains incorrect value. Expected 'X9f2M4pL1vQ8z', got '{content}'"

    st = os.stat(token_path)
    permissions = stat.S_IMODE(st.st_mode)
    assert permissions == 0o400, f"Token file permissions are incorrect. Expected 0o400, got {oct(permissions)}"

def test_final_report_json():
    report_path = '/home/user/final_report.json'
    assert os.path.isfile(report_path), f"Final report {report_path} is missing."

    with open(report_path, 'r') as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"Final report {report_path} is not valid JSON.")

    expected_data = {
        "scanned_files": 3,
        "blocked_files": 2,
        "allowed_files": 1,
        "extracted_token": "X9f2M4pL1vQ8z"
    }

    assert data == expected_data, f"Final report JSON contents are incorrect. Expected {expected_data}, got {data}"
TEST_EOF

cat << 'DYNAMIC_EOF' > /tmp/test_dynamic_execution.py
import hashlib
import json
import os
import secrets
import shutil
import stat
import subprocess
import tempfile

HOME = '/home/user'
SOURCE = os.path.join(HOME, 'analyze.go')
INTERCEPTED = os.path.join(HOME, 'intercepted')
INTEL = os.path.join(HOME, 'threat_intel.db')
OUTPUTS = [
    os.path.join(HOME, 'firewall_policy.log'),
    os.path.join(HOME, 'safe_token.txt'),
    os.path.join(HOME, 'final_report.json'),
]
BINARY = '/tmp/analyze_submission'

assert os.path.exists(SOURCE), 'Required Go source /home/user/analyze.go is missing.'
assert stat.S_ISREG(os.lstat(SOURCE).st_mode), '/home/user/analyze.go must be a regular file.'
assert os.path.getsize(SOURCE) > 0, '/home/user/analyze.go is empty.'

subprocess.run(
    ['go', 'build', '-o', BINARY, SOURCE],
    cwd=HOME,
    check=True,
    timeout=60,
    stdout=subprocess.PIPE,
    stderr=subprocess.PIPE,
)

backup_root = tempfile.mkdtemp(prefix='analyze-verifier-')
backup_intercepted = os.path.join(backup_root, 'intercepted')
shutil.copytree(INTERCEPTED, backup_intercepted, copy_function=shutil.copy2)

def snapshot(path):
    st = os.stat(path)
    with open(path, 'rb') as f:
        return f.read(), stat.S_IMODE(st.st_mode), st.st_uid, st.st_gid

intel_backup = snapshot(INTEL)
output_backups = {path: snapshot(path) for path in OUTPUTS}

try:
    suffix = secrets.token_hex(5)
    names = [f'capture_{suffix}_{i}.bin' for i in range(3)]
    tokens = [secrets.token_urlsafe(12).replace('-', 'A').replace('_', 'B') for _ in range(3)]
    plaintexts = [
        b'BUFFER_' + secrets.token_bytes(9).hex().encode() +
        b'_SECRET_ACCESS_TOKEN=' + token.encode() + b'_ENDING_SEQUENCE'
        for token in tokens
    ]
    ciphertexts = [bytes(byte ^ 0x7A for byte in plaintext) for plaintext in plaintexts]

    shutil.rmtree(INTERCEPTED)
    os.mkdir(INTERCEPTED, 0o755)
    for name, content in zip(names, ciphertexts):
        with open(os.path.join(INTERCEPTED, name), 'wb') as f:
            f.write(content)

    # The same three files are tested twice with different threat databases. All
    # three decrypt to token-shaped payloads, so only hash/database comparison
    # identifies which token belongs to the allowed payload.
    for allowed_index in (0, 2):
        blocked_indices = [i for i in range(3) if i != allowed_index]
        with open(INTEL, 'w', encoding='ascii', newline='\n') as f:
            for i in blocked_indices:
                f.write(hashlib.sha256(ciphertexts[i]).hexdigest() + '\n')

        for output in OUTPUTS:
            try:
                os.remove(output)
            except FileNotFoundError:
                pass

        subprocess.run(
            [BINARY],
            cwd=HOME,
            check=True,
            timeout=30,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
        )

        log_path, token_path, report_path = OUTPUTS
        assert os.path.isfile(log_path), 'Scanner did not generate firewall_policy.log.'
        with open(log_path, 'r', encoding='utf-8') as f:
            lines = [line.strip() for line in f if line.strip()]
        expected_lines = {
            ('ALLOW' if i == allowed_index else 'BLOCK') +
            ' ' + os.path.join(INTERCEPTED, names[i])
            for i in range(3)
        }
        assert len(lines) == 3, f'Expected exactly three policy lines, got {lines!r}'
        assert set(lines) == expected_lines, f'Dynamic policy is incorrect: {lines!r}'

        assert os.path.isfile(token_path), 'Scanner did not generate safe_token.txt.'
        with open(token_path, 'rb') as f:
            token_bytes = f.read()
        expected_token = tokens[allowed_index].encode()
        assert token_bytes == expected_token, 'Scanner did not XOR-decrypt and extract the allowed payload token exactly.'
        assert stat.S_IMODE(os.stat(token_path).st_mode) == 0o400, 'safe_token.txt is not mode 0400.'

        assert os.path.isfile(report_path), 'Scanner did not generate final_report.json.'
        with open(report_path, 'r', encoding='utf-8') as f:
            report = json.load(f)
        assert report == {
            'scanned_files': 3,
            'blocked_files': 2,
            'allowed_files': 1,
            'extracted_token': tokens[allowed_index],
        }, f'Dynamic report is incorrect: {report!r}'
finally:
    shutil.rmtree(INTERCEPTED, ignore_errors=True)
    shutil.copytree(backup_intercepted, INTERCEPTED, copy_function=shutil.copy2)

    def restore(path, saved):
        data, mode, uid, gid = saved
        with open(path, 'wb') as f:
            f.write(data)
        os.chmod(path, mode)
        os.chown(path, uid, gid)

    restore(INTEL, intel_backup)
    for path, saved in output_backups.items():
        restore(path, saved)
    shutil.rmtree(backup_root, ignore_errors=True)
    try:
        os.remove(BINARY)
    except FileNotFoundError:
        pass
DYNAMIC_EOF

status=0
python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1 || status=1
if [ "$status" -eq 0 ]; then
    python3 /tmp/test_dynamic_execution.py 2>&1 || status=1
fi

if [ "$status" -eq 0 ]; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
