#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import fnmatch
import json
import os
import secrets
import shlex
import subprocess


def test_ssh_keys_generated():
    private_key = '/home/user/.ssh/log_backup_key'
    public_key = '/home/user/.ssh/log_backup_key.pub'

    assert os.path.exists(private_key), f"Private key missing at {private_key}"
    assert os.path.exists(public_key), f"Public key missing at {public_key}"

    with open(private_key, 'r') as f:
        content = f.read()
        assert 'OPENSSH PRIVATE KEY' in content, "The private key is not a valid OpenSSH format (expected Ed25519)."

    derived = subprocess.run(
        ['ssh-keygen', '-y', '-P', '', '-f', private_key],
        text=True, capture_output=True, timeout=10
    )
    assert derived.returncode == 0, f"Private key is invalid or passphrase-protected: {derived.stderr}"
    derived_parts = derived.stdout.strip().split()
    assert len(derived_parts) >= 2 and derived_parts[0] == 'ssh-ed25519', "Private key is not Ed25519."

    with open(public_key, 'r') as f:
        public_parts = f.read().strip().split()
    assert len(public_parts) >= 2, "Public key is not a valid OpenSSH public key."
    assert public_parts[0] == 'ssh-ed25519', "Public key is not Ed25519."
    assert public_parts[:2] == derived_parts[:2], "Public key does not match the private key."


def test_ssh_config_hardened():
    config_path = '/home/user/.ssh/config'
    assert os.path.exists(config_path), f"SSH config missing at {config_path}"

    with open(config_path, 'r') as f:
        config_content = f.read().lower()

    assert 'host backup.local' in config_content, "Host backup.local is not configured in SSH config."
    assert 'passwordauthentication no' in config_content, "PasswordAuthentication is not set to 'no'."
    assert 'identityfile /home/user/.ssh/log_backup_key' in config_content, "IdentityFile is not properly set to the generated key."

    host_entries = []
    with open(config_path, 'r') as f:
        for raw_line in f:
            try:
                tokens = shlex.split(raw_line, comments=True, posix=True)
            except ValueError as exc:
                assert False, f"Invalid SSH config syntax: {exc}"
            if tokens and tokens[0].lower() == 'host':
                host_entries.append([token.lower() for token in tokens[1:]])
    assert any(
        any(not pattern.startswith('!') and fnmatch.fnmatchcase('backup.local', pattern) for pattern in patterns)
        and any(pattern == 'backup.local' for pattern in patterns)
        for patterns in host_entries
    ), "SSH config has no real Host backup.local entry."

    resolved = subprocess.run(
        ['runuser', '-u', 'user', '--', 'ssh', '-G', '-F', config_path, 'backup.local'],
        text=True, capture_output=True, timeout=10
    )
    assert resolved.returncode == 0, f"SSH config cannot be parsed: {resolved.stderr}"
    effective = {}
    for line in resolved.stdout.splitlines():
        parts = line.strip().split(None, 1)
        if len(parts) == 2:
            effective.setdefault(parts[0].lower(), []).append(parts[1])
    assert effective.get('passwordauthentication') == ['no'], "PasswordAuthentication is not effectively disabled for backup.local."
    assert '/home/user/.ssh/log_backup_key' in effective.get('identityfile', []), "The requested IdentityFile is not effective for backup.local."


def test_redacted_logs_content():
    script_path = '/home/user/redactor.py'
    assert os.path.isfile(script_path), f"Redaction script missing at {script_path}"

    redacted_path = '/home/user/redacted_logs.jsonl'
    assert os.path.exists(redacted_path), f"Redacted logs file missing at {redacted_path}"

    expected_logs = [
        {"timestamp": "2023-10-01T12:00:00Z", "method": "GET", "url": "/profile", "headers": {"Host": "example.com", "Authorization": "[REDACTED]", "Cookie": "theme=dark; session_id=[REDACTED]; lang=en", "User-Agent": "curl/7.68.0"}},
        {"timestamp": "2023-10-01T12:00:05Z", "method": "POST", "url": "/login", "headers": {"Host": "example.com", "Content-Type": "application/json"}},
        {"timestamp": "2023-10-01T12:00:10Z", "method": "GET", "url": "/dashboard", "headers": {"Host": "example.com", "Cookie": "session_id=[REDACTED]; active=true", "Authorization": "[REDACTED]"}}
    ]

    actual_logs = []
    with open(redacted_path, 'r') as f:
        for line in f:
            if line.strip():
                try:
                    actual_logs.append(json.loads(line))
                except json.JSONDecodeError:
                    assert False, f"Line in {redacted_path} is not valid JSON."

    assert len(actual_logs) == len(expected_logs), f"Expected {len(expected_logs)} lines in redacted logs, found {len(actual_logs)}."

    for i, (actual, expected) in enumerate(zip(actual_logs, expected_logs)):
        assert actual == expected, f"Log entry at line {i+1} does not match expected redaction.\nExpected: {expected}\nActual: {actual}"


def test_redactor_executes_on_derived_inputs():
    raw_path = '/home/user/raw_logs.jsonl'
    redacted_path = '/home/user/redacted_logs.jsonl'
    script_path = '/home/user/redactor.py'
    assert os.path.isfile(script_path), f"Redaction script missing at {script_path}"

    raw_original = open(raw_path, 'rb').read()
    output_existed = os.path.exists(redacted_path)
    output_original = open(redacted_path, 'rb').read() if output_existed else None

    auth_one = 'Bearer-' + secrets.token_hex(18)
    auth_two = 'Basic-' + secrets.token_hex(15)
    session_one = secrets.token_hex(17)
    session_two = secrets.token_hex(19)
    challenge = [
        {"marker": secrets.token_hex(8), "headers": {"Cookie": f"theme=dark; session_id={session_one}; lang=en", "Authorization": auth_one, "X-Keep": "unchanged"}, "nested": {"keep": [1, 2, 3]}},
        {"marker": secrets.token_hex(8), "headers": {"Host": "dynamic.example", "Cookie": "theme=light; active=true"}},
        {"marker": secrets.token_hex(8), "headers": {"Authorization": auth_two, "Cookie": f"session_id={session_two}; active=true"}}
    ]
    expected = json.loads(json.dumps(challenge))
    expected[0]['headers']['Authorization'] = '[REDACTED]'
    expected[0]['headers']['Cookie'] = 'theme=dark; session_id=[REDACTED]; lang=en'
    expected[2]['headers']['Authorization'] = '[REDACTED]'
    expected[2]['headers']['Cookie'] = 'session_id=[REDACTED]; active=true'

    try:
        with open(raw_path, 'w') as f:
            for entry in challenge:
                f.write(json.dumps(entry) + '\n')
        if os.path.exists(redacted_path):
            os.remove(redacted_path)

        result = subprocess.run(
            ['python3', script_path], cwd='/home/user', text=True,
            capture_output=True, timeout=15
        )
        assert result.returncode == 0, f"redactor.py failed when executed: {result.stderr}"
        assert os.path.isfile(redacted_path), "Executing redactor.py did not create redacted_logs.jsonl."

        actual = []
        with open(redacted_path, 'r') as f:
            for line in f:
                if line.strip():
                    try:
                        actual.append(json.loads(line))
                    except json.JSONDecodeError as exc:
                        assert False, f"redactor.py produced invalid JSON: {exc}"
        assert actual == expected, f"redactor.py did not correctly redact derived input.\nExpected: {expected}\nActual: {actual}"
    finally:
        with open(raw_path, 'wb') as f:
            f.write(raw_original)
        if output_existed:
            with open(redacted_path, 'wb') as f:
                f.write(output_original)
        elif os.path.exists(redacted_path):
            os.remove(redacted_path)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
