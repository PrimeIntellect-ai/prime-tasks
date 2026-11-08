#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import hashlib
import json
import os
import pwd
import secrets
import shutil
import subprocess

from cryptography.fernet import Fernet

EXPECTED_SECRET = None
EXPECTED_CHECKSUM = None


def test_recover_script_exists():
    """Test that the recover.py script was created and is not empty."""
    script_path = '/home/user/forensics/recover.py'
    assert os.path.isfile(script_path), f"Script {script_path} is missing. You need to create it."
    assert os.path.getsize(script_path) > 0, f"Script {script_path} is empty."


def test_recover_script_executes_on_fresh_evidence():
    """Execute the submitted script against fresh evidence and a fresh key."""
    global EXPECTED_SECRET, EXPECTED_CHECKSUM

    script_path = '/home/user/forensics/recover.py'
    with open(script_path, 'rb') as f:
        script_data = f.read()

    forensics_dir = '/home/user/forensics'
    backup_dir = '/home/user/system_backup'

    if os.path.lexists(forensics_dir):
        if os.path.isdir(forensics_dir) and not os.path.islink(forensics_dir):
            shutil.rmtree(forensics_dir)
        else:
            os.unlink(forensics_dir)
    os.makedirs(forensics_dir, mode=0o777)
    os.chmod(forensics_dir, 0o777)

    with open(script_path, 'wb') as f:
        f.write(script_data)
    os.chmod(script_path, 0o755)

    if os.path.lexists(backup_dir):
        if os.path.isdir(backup_dir) and not os.path.islink(backup_dir):
            shutil.rmtree(backup_dir)
        else:
            os.unlink(backup_dir)

    key_dir = '/home/user/system_backup/app_data/tmp'
    os.makedirs(key_dir, mode=0o755)
    os.chmod('/home/user/system_backup', 0o755)
    os.chmod('/home/user/system_backup/app_data', 0o755)
    os.chmod(key_dir, 0o755)

    key = Fernet.generate_key()
    key_path = os.path.join(key_dir, '.key_backup')
    with open(key_path, 'wb') as f:
        f.write(key)
    os.chmod(key_path, 0o644)

    EXPECTED_SECRET = 'CTF{verification_' + secrets.token_hex(24) + '}'
    evidence_data = {
        'id': secrets.randbelow(1000000),
        'secret_evidence': EXPECTED_SECRET,
        'timestamp': '2023-10-25T14:32:00Z',
        'distractor': secrets.token_hex(16),
    }
    encrypted_evidence = Fernet(key).encrypt(json.dumps(evidence_data).encode('utf-8'))
    with open('/home/user/forensics/evidence.enc', 'wb') as f:
        f.write(encrypted_evidence)
    os.chmod('/home/user/forensics/evidence.enc', 0o644)

    EXPECTED_CHECKSUM = hashlib.sha256(EXPECTED_SECRET.encode('utf-8')).hexdigest()
    with open('/home/user/forensics/checksum.txt', 'w', encoding='utf-8') as f:
        f.write(EXPECTED_CHECKSUM)
    os.chmod('/home/user/forensics/checksum.txt', 0o644)

    user = pwd.getpwnam('user')

    def demote():
        os.initgroups(user.pw_name, user.pw_gid)
        os.setgid(user.pw_gid)
        os.setuid(user.pw_uid)

    result = subprocess.run(
        ['python3', script_path],
        cwd=forensics_dir,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=20,
        preexec_fn=demote,
    )
    assert result.returncode == 0, (
        f'recover.py exited with status {result.returncode}. '
        f'stdout: {result.stdout!r}; stderr: {result.stderr!r}'
    )


def test_flag_file_exists_and_correct():
    """Test that flag.txt contains exactly the freshly decrypted value."""
    flag_path = '/home/user/forensics/flag.txt'
    checksum_path = '/home/user/forensics/checksum.txt'

    assert os.path.isfile(flag_path), f"Flag file {flag_path} is missing. Did your script run and produce it?"
    assert os.path.isfile(checksum_path), f"Checksum file {checksum_path} is missing."

    with open(flag_path, 'r', encoding='utf-8') as f:
        flag_content = f.read()

    with open(checksum_path, 'r', encoding='utf-8') as f:
        expected_checksum = f.read().strip()

    actual_checksum = hashlib.sha256(flag_content.encode('utf-8')).hexdigest()

    assert actual_checksum == expected_checksum, (
        f"The SHA-256 checksum of the contents in {flag_path} does not match the expected checksum in {checksum_path}. "
        "Ensure that you extracted the correct value and that there are no trailing newlines or extra spaces in your output file."
    )
    assert expected_checksum == EXPECTED_CHECKSUM, 'recover.py modified the supplied checksum.'
    assert flag_content == EXPECTED_SECRET, (
        'flag.txt does not contain exactly the secret_evidence value from the freshly encrypted evidence.'
    )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
