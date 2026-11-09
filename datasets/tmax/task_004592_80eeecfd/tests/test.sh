#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import stat
import hashlib
import sys
import secrets


def test_cracked_password():
    password_file = "/home/user/cracked_password.txt"
    assert os.path.isfile(password_file), f"The file {password_file} does not exist."
    with open(password_file, "r") as f:
        content = f.read().strip()
    assert content == "sunshine", f"The cracked password file should contain exactly 'sunshine', but contains '{content}'."


def test_login_py_behavior():
    login_file = "/home/user/app/login.py"
    assert os.path.isfile(login_file), f"The file {login_file} does not exist."

    sys.path.append('/home/user/app')
    try:
        from login import get_redirect_url
    except ImportError:
        assert False, "Could not import get_redirect_url from /home/user/app/login.py"

    # Original exact test cases.
    assert get_redirect_url('/dashboard') == '/dashboard', "Failed on valid relative path"
    assert get_redirect_url('//evil.com') == '/home', "Failed on protocol-relative path"
    assert get_redirect_url('https://evil.com') == '/home', "Failed on absolute URL"
    assert get_redirect_url(None) == '/home', "Failed on None"
    assert get_redirect_url('') == '/home', "Failed on empty string"

    # Exercise the general policy with unpredictable values rather than a fixed subset.
    cases = [('/', '/')]
    for _ in range(40):
        component = secrets.token_hex(16)
        nested = secrets.token_hex(8)
        valid_path = f"/{component}/{nested}?q={secrets.token_hex(4)}"
        cases.append((valid_path, valid_path))
        cases.append((f"//{component}.example/{nested}", '/home'))
        cases.append((f"{component}/{nested}", '/home'))
        cases.append((f"https://{component}.example/{nested}", '/home'))

    for value, expected in cases:
        actual = get_redirect_url(value)
        assert actual == expected, (
            f"get_redirect_url({value!r}) returned {actual!r}; expected {expected!r}"
        )


def test_config_json_permissions():
    config_file = "/home/user/app/config.json"
    assert os.path.isfile(config_file), f"The file {config_file} does not exist."

    st = os.stat(config_file)
    perms = stat.S_IMODE(st.st_mode)
    assert perms == 0o600, f"The file {config_file} must have permissions 600, but has {oct(perms)}."


def test_audit_log():
    audit_log = "/home/user/audit_log.txt"
    login_file = "/home/user/app/login.py"

    assert os.path.isfile(audit_log), f"The file {audit_log} does not exist."
    assert os.path.isfile(login_file), f"The file {login_file} does not exist."

    with open(login_file, "rb") as f:
        login_content = f.read()
    expected_hash = hashlib.sha256(login_content).hexdigest()

    with open(audit_log, "r") as f:
        lines = [line.strip() for line in f.readlines()]

    assert len(lines) == 3, f"The audit log must have exactly 3 lines, but found {len(lines)}."
    assert lines[0] == "sunshine", f"Line 1 of audit log should be 'sunshine', but is '{lines[0]}'."
    assert lines[1] == "600", f"Line 2 of audit log should be '600', but is '{lines[1]}'."
    assert lines[2] == expected_hash, f"Line 3 of audit log should be the SHA256 hash of login.py ({expected_hash}), but is '{lines[2]}'."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
