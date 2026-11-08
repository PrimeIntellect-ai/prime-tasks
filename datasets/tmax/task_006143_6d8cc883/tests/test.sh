#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import json
import secrets
import subprocess
import tempfile
from pathlib import Path
import pytest

def test_aliases_file_content():
    path = '/home/user/aliases'
    assert os.path.isfile(path), f"File {path} does not exist"

    with open(path, 'r') as f:
        lines = [line.strip() for line in f if line.strip()]

    expected_lines = [
        "list-admin: admin@localdomain.internal",
        "list-alice: alice@localdomain.internal",
        "list-bob: bob@localdomain.internal"
    ]

    for expected in expected_lines:
        assert expected in lines, f"Expected line '{expected}' not found in {path}"

    assert len(lines) == len(expected_lines), f"File {path} contains unexpected or duplicate lines. Found {len(lines)} lines, expected {len(expected_lines)}."

def test_firewall_rules_file_content():
    path = '/home/user/firewall.rules'
    assert os.path.isfile(path), f"File {path} does not exist"

    with open(path, 'r') as f:
        lines = [line.strip() for line in f if line.strip()]

    expected_lines = [
        "-A PREROUTING -p tcp --dport 8080 -j REDIRECT --to-ports 2525",
        "-A PREROUTING -p tcp --dport 8081 -j REDIRECT --to-ports 2525",
        "-A PREROUTING -p tcp --dport 8082 -j REDIRECT --to-ports 2525"
    ]

    for expected in expected_lines:
        assert expected in lines, f"Expected line '{expected}' not found in {path}"

    assert len(lines) == len(expected_lines), f"File {path} contains unexpected or duplicate lines. Found {len(lines)} lines, expected {len(expected_lines)}."

def test_update_users_script_absolute_paths():
    path = '/home/user/update_users.py'
    assert os.path.isfile(path), f"File {path} does not exist"

    with open(path, 'r') as f:
        content = f.read()

    assert "'/home/user/user_db.json'" in content or '"/home/user/user_db.json"' in content, "Script does not use absolute path for user_db.json"
    assert "'/home/user/aliases'" in content or '"/home/user/aliases"' in content, "Script does not use absolute path for aliases"
    assert "'/home/user/firewall.rules'" in content or '"/home/user/firewall.rules"' in content, "Script does not use absolute path for firewall.rules"

def test_idempotency_no_duplicates():
    aliases_path = '/home/user/aliases'
    firewall_path = '/home/user/firewall.rules'

    with open(aliases_path, 'r') as f:
        aliases_lines = [line.strip() for line in f if line.strip()]
    assert len(aliases_lines) == len(set(aliases_lines)), f"Duplicate lines found in {aliases_path}, script is not idempotent."

    with open(firewall_path, 'r') as f:
        firewall_lines = [line.strip() for line in f if line.strip()]
    assert len(firewall_lines) == len(set(firewall_lines)), f"Duplicate lines found in {firewall_path}, script is not idempotent."

def test_script_executes_from_other_directory_and_is_idempotent():
    script = Path('/home/user/update_users.py')
    db = Path('/home/user/user_db.json')
    aliases = Path('/home/user/aliases')
    firewall = Path('/home/user/firewall.rules')

    assert script.is_file(), f"File {script} does not exist"

    originals = {
        db: db.read_bytes(),
        aliases: aliases.read_bytes(),
        firewall: firewall.read_bytes(),
    }

    token = secrets.token_hex(8)
    users = [
        {"username": f"verify_{token}_one", "port": 20000 + secrets.randbelow(10000)},
        {"username": f"verify_{token}_two", "port": 40000 + secrets.randbelow(10000)},
    ]
    seed_alias = "list-admin: admin@localdomain.internal"
    seed_rule = "-A PREROUTING -p tcp --dport 8080 -j REDIRECT --to-ports 2525"
    expected_aliases = [seed_alias] + [
        f"list-{u['username']}: {u['username']}@localdomain.internal" for u in users
    ]
    expected_rules = [seed_rule] + [
        f"-A PREROUTING -p tcp --dport {u['port']} -j REDIRECT --to-ports 2525" for u in users
    ]

    try:
        db.write_text(json.dumps(users), encoding='utf-8')
        aliases.write_text(seed_alias + "\n", encoding='utf-8')
        firewall.write_text(seed_rule + "\n", encoding='utf-8')

        with tempfile.TemporaryDirectory() as other_cwd:
            subprocess.run(
                ['python3', str(script)], cwd=other_cwd, check=True,
                stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, timeout=15
            )

            first_alias_bytes = aliases.read_bytes()
            first_firewall_bytes = firewall.read_bytes()
            alias_lines = [line.strip() for line in aliases.read_text(encoding='utf-8').splitlines() if line.strip()]
            firewall_lines = [line.strip() for line in firewall.read_text(encoding='utf-8').splitlines() if line.strip()]
            assert alias_lines == expected_aliases
            assert firewall_lines == expected_rules

            subprocess.run(
                ['python3', str(script)], cwd=other_cwd, check=True,
                stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, timeout=15
            )

            assert aliases.read_bytes() == first_alias_bytes, "Second run changed aliases; script is not idempotent"
            assert firewall.read_bytes() == first_firewall_bytes, "Second run changed firewall rules; script is not idempotent"
            alias_lines = [line.strip() for line in aliases.read_text(encoding='utf-8').splitlines() if line.strip()]
            firewall_lines = [line.strip() for line in firewall.read_text(encoding='utf-8').splitlines() if line.strip()]
            assert alias_lines == expected_aliases
            assert firewall_lines == expected_rules
    finally:
        for path, content in originals.items():
            path.write_bytes(content)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
