#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import ast
import hashlib
import json
import os
import secrets
import subprocess

ROTATE_PATH = '/home/user/rotate.py'
OLD_CONFIG_PATH = '/home/user/old_config.json'
WORDLIST_PATH = '/home/user/wordlist.txt'
NEW_CONFIG_PATH = '/home/user/new_config.json'


def assert_uses_secure_random_source(source):
    try:
        tree = ast.parse(source, filename=ROTATE_PATH)
    except SyntaxError as exc:
        assert False, f"rotate.py is not valid Python: {exc}"

    module_aliases = {}
    direct_secure_calls = set()
    secure_members = {
        'secrets': {'token_bytes', 'token_hex', 'choice', 'randbelow', 'randbits', 'SystemRandom'},
        'os': {'urandom'},
        'random': {'SystemRandom'},
        'ssl': {'RAND_bytes'},
    }

    for node in ast.walk(tree):
        if isinstance(node, ast.Import):
            for item in node.names:
                if item.name in secure_members:
                    module_aliases[item.asname or item.name] = item.name
        elif isinstance(node, ast.ImportFrom) and node.module in secure_members:
            for item in node.names:
                if item.name in secure_members[node.module]:
                    direct_secure_calls.add(item.asname or item.name)

    found = False
    for node in ast.walk(tree):
        if not isinstance(node, ast.Call):
            continue
        if isinstance(node.func, ast.Name) and node.func.id in direct_secure_calls:
            found = True
        elif isinstance(node.func, ast.Attribute) and isinstance(node.func.value, ast.Name):
            module = module_aliases.get(node.func.value.id)
            if module and node.func.attr in secure_members[module]:
                found = True

    # Reading the operating system CSPRNG directly is also valid.
    if '/dev/urandom' in {
        node.value for node in ast.walk(tree)
        if isinstance(node, ast.Constant) and isinstance(node.value, str)
    }:
        found = True

    assert found, "rotate.py must use a cryptographically secure random source for the salt"


def run_rotate():
    if os.path.exists(NEW_CONFIG_PATH):
        os.remove(NEW_CONFIG_PATH)
    result = subprocess.run(
        ['python3', ROTATE_PATH],
        cwd='/home/user',
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=15,
    )
    assert result.returncode == 0, (
        f"rotate.py failed with exit code {result.returncode}: {result.stderr}"
    )
    assert os.path.isfile(NEW_CONFIG_PATH), "rotate.py did not create new_config.json"
    with open(NEW_CONFIG_PATH, 'r') as f:
        try:
            return json.load(f)
        except json.JSONDecodeError as exc:
            assert False, f"rotate.py created invalid JSON: {exc}"


def assert_generated_config(data, password, wordlist_bytes):
    assert data.get('service') == 'db'
    assert data.get('recovered_password_length') == len(password)
    assert data.get('new_hash_algorithm') == 'sha256'

    salt = data.get('salt')
    assert isinstance(salt, str) and len(salt) == 32, "Salt must be 32 hex characters"
    try:
        salt_bytes = bytes.fromhex(salt)
    except ValueError:
        assert False, "Salt must be valid hexadecimal"
    assert len(salt_bytes) == 16, "Salt must encode exactly 16 bytes"

    expected_hash = hashlib.sha256((salt + password).encode('utf-8')).hexdigest()
    assert data.get('password_hash') == expected_hash
    assert data.get('wordlist_checksum') == hashlib.sha256(wordlist_bytes).hexdigest()
    return salt


def test_rotate_script_cracks_and_generates_secure_salts():
    assert os.path.isfile(ROTATE_PATH), f"File not found: {ROTATE_PATH}"
    with open(ROTATE_PATH, 'r', encoding='utf-8') as f:
        source = f.read()
    assert_uses_secure_random_source(source)

    with open(OLD_CONFIG_PATH, 'rb') as f:
        original_old_config = f.read()
    with open(WORDLIST_PATH, 'rb') as f:
        original_wordlist = f.read()

    test_password = 'verify-' + secrets.token_hex(6)
    test_wordlist = (
        'not-the-password\nfirst-decoy\n' + test_password + '\nlast-decoy\n'
    ).encode('utf-8')
    test_old_config = {
        'service': 'db',
        'hash_algorithm': 'md5',
        'password_hash': hashlib.md5(test_password.encode('utf-8')).hexdigest(),
    }

    try:
        with open(OLD_CONFIG_PATH, 'w', encoding='utf-8') as f:
            json.dump(test_old_config, f)
        with open(WORDLIST_PATH, 'wb') as f:
            f.write(test_wordlist)

        salts = []
        for _ in range(3):
            data = run_rotate()
            salts.append(assert_generated_config(data, test_password, test_wordlist))
        assert len(set(salts)) == 3, "rotate.py reused or deterministically fixed the salt"
    finally:
        with open(OLD_CONFIG_PATH, 'wb') as f:
            f.write(original_old_config)
        with open(WORDLIST_PATH, 'wb') as f:
            f.write(original_wordlist)

    # Produce the required final artifact from the restored, original inputs.
    final_data = run_rotate()
    assert_generated_config(final_data, 'hunter2', original_wordlist)


def test_new_config_exists_and_valid():
    new_config_path = '/home/user/new_config.json'
    assert os.path.isfile(new_config_path), f"File not found: {new_config_path}"

    with open(new_config_path, 'r') as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            assert False, f"File {new_config_path} is not valid JSON"

    assert "service" in data, "Key 'service' missing in new_config.json"
    assert data["service"] == "db", f"Expected service to be 'db', got {data['service']}"

    assert "recovered_password_length" in data, "Key 'recovered_password_length' missing"
    assert data["recovered_password_length"] == 7, f"Expected recovered_password_length to be 7, got {data['recovered_password_length']}"

    assert "new_hash_algorithm" in data, "Key 'new_hash_algorithm' missing"
    assert data["new_hash_algorithm"] == "sha256", f"Expected new_hash_algorithm to be 'sha256', got {data['new_hash_algorithm']}"

    assert "salt" in data, "Key 'salt' missing"
    salt = data["salt"]
    assert isinstance(salt, str) and len(salt) == 32, "Salt must be a 32-character string"
    try:
        int(salt, 16)
    except ValueError:
        assert False, "Salt must be a valid hex string"

    assert "password_hash" in data, "Key 'password_hash' missing"
    expected_hash = hashlib.sha256((salt + 'hunter2').encode('utf-8')).hexdigest()
    assert data["password_hash"] == expected_hash, f"password_hash does not match expected sha256(salt + password)"

    assert "wordlist_checksum" in data, "Key 'wordlist_checksum' missing"

    wordlist_path = '/home/user/wordlist.txt'
    assert os.path.isfile(wordlist_path), f"Original file {wordlist_path} was deleted or moved"

    with open(wordlist_path, 'rb') as f:
        expected_wordlist_checksum = hashlib.sha256(f.read()).hexdigest()

    assert data["wordlist_checksum"] == expected_wordlist_checksum, "wordlist_checksum does not match the actual SHA256 checksum of wordlist.txt"


def test_original_files_unmodified():
    old_config_path = '/home/user/old_config.json'
    assert os.path.isfile(old_config_path), f"Original file {old_config_path} was deleted or moved"
    with open(old_config_path, 'r') as f:
        data = json.load(f)
    assert data.get("password_hash") == "2ab96390c7dbe3439de74d0c9b0b1767", "old_config.json was modified"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
