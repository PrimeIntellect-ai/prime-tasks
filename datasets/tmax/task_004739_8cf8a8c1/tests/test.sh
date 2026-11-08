#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import secrets
import string
import subprocess
import tempfile
from pathlib import Path
import pytest

CRED_PATTERN = re.compile(rb'TRK-[A-Z0-9]{6}-[A-Z0-9]{6}')
KEY_PATTERN = re.compile(
    rb'-----BEGIN OPENSSH PRIVATE KEY-----.*?-----END OPENSSH PRIVATE KEY-----',
    re.DOTALL,
)


def expected_sanitized(data):
    data = CRED_PATTERN.sub(b'[REDACTED_CRED]', data)
    return KEY_PATTERN.sub(b'[REDACTED_KEY]', data)


def run_sanitizer(script_path, data):
    with tempfile.NamedTemporaryFile(prefix='audit-', suffix='.log', delete=False) as f:
        f.write(data)
        input_path = f.name
    try:
        return subprocess.run(
            ['python3', str(script_path), input_path],
            capture_output=True,
            timeout=10,
        )
    finally:
        os.unlink(input_path)


def test_ssh_hardening():
    """Verify SSH key generation and config hardening."""
    ssh_dir = Path('/home/user/.ssh')
    key_path = ssh_dir / 'audit_id_ed25519'
    public_key_path = ssh_dir / 'audit_id_ed25519.pub'
    config_path = ssh_dir / 'config'

    assert key_path.exists(), f'SSH key not found at {key_path}'
    assert config_path.exists(), f'SSH config not found at {config_path}'
    assert key_path.is_file(), 'SSH private key path is not a regular file'
    assert public_key_path.is_file(), 'SSH public key was not generated'
    assert config_path.is_file(), 'SSH config path is not a regular file'

    config_content = config_path.read_text()

    # Keep the original directive assertions.
    assert re.search(r'(?i)^\s*PasswordAuthentication\s+no\b', config_content, re.MULTILINE), \
        "SSH config missing 'PasswordAuthentication no'"
    assert re.search(r'(?i)^\s*Ciphers\s+chacha20-poly1305@openssh\.com\b', config_content, re.MULTILINE), \
        "SSH config missing 'Ciphers chacha20-poly1305@openssh.com'"
    assert re.search(r'(?i)^\s*IdentityFile\s+(~|/home/user)/\.ssh/audit_id_ed25519\b', config_content, re.MULTILINE), \
        "SSH config missing correct 'IdentityFile' directive"

    # Require a genuine, unencrypted ed25519 keypair whose public key matches.
    derived = subprocess.run(
        ['ssh-keygen', '-y', '-f', str(key_path)],
        input=b'', capture_output=True, timeout=10,
    )
    assert derived.returncode == 0, 'Private key is invalid or passphrase-protected'
    derived_fields = derived.stdout.strip().split()
    public_fields = public_key_path.read_bytes().strip().split()
    assert len(derived_fields) >= 2 and derived_fields[0] == b'ssh-ed25519', \
        'Private key is not an ed25519 key'
    assert len(public_fields) >= 2 and public_fields[:2] == derived_fields[:2], \
        'Public key does not match the private key'

    # Require all directives to occur in an actual `Host *` block.
    blocks = []
    current_patterns = None
    current_lines = []
    for raw_line in config_content.splitlines():
        line = raw_line.split('#', 1)[0].strip()
        if not line:
            continue
        parts = line.split()
        if parts[0].lower() == 'host':
            if current_patterns is not None:
                blocks.append((current_patterns, current_lines))
            current_patterns = parts[1:]
            current_lines = []
        elif current_patterns is not None:
            current_lines.append(line)
    if current_patterns is not None:
        blocks.append((current_patterns, current_lines))

    star_blocks = [lines for patterns, lines in blocks if '*' in patterns]
    assert star_blocks, "SSH config is missing an explicit 'Host *' block"
    valid_star_block = False
    for lines in star_blocks:
        text = '\n'.join(lines)
        if (re.search(r'(?i)^\s*PasswordAuthentication\s+no\b', text, re.MULTILINE)
                and re.search(r'(?i)^\s*Ciphers\s+chacha20-poly1305@openssh\.com\b', text, re.MULTILINE)
                and re.search(r'(?i)^\s*IdentityFile\s+(~|/home/user)/\.ssh/audit_id_ed25519\b', text, re.MULTILINE)):
            valid_star_block = True
            break
    assert valid_star_block, 'Required directives are not all scoped under Host *'


def test_sanitizer_adversarial_corpus():
    """Verify exact sanitizer output against supplied and generated corpora."""
    script_path = Path('/home/user/sanitizer.py')
    assert script_path.exists(), f'Sanitizer script not found at {script_path}'
    assert script_path.is_file(), f'Sanitizer path is not a file: {script_path}'

    clean_dir = Path('/app/corpus/clean')
    evil_dir = Path('/app/corpus/evil')
    assert clean_dir.exists() and clean_dir.is_dir(), 'Clean corpus directory missing'
    assert evil_dir.exists() and evil_dir.is_dir(), 'Evil corpus directory missing'

    clean_files = list(clean_dir.iterdir())
    failed_clean = []
    for f in clean_files:
        if not f.is_file():
            continue
        original_content = f.read_bytes()
        result = subprocess.run(['python3', str(script_path), str(f)], capture_output=True, timeout=10)
        if result.returncode != 0 or result.stdout != original_content:
            failed_clean.append(f.name)

    evil_files = list(evil_dir.iterdir())
    failed_evil = []
    regex_pattern = re.compile(rb'TRK-[A-Z0-9]{6}-[A-Z0-9]{6}')
    ssh_key_pattern = b'BEGIN OPENSSH PRIVATE KEY'
    for f in evil_files:
        if not f.is_file():
            continue
        original_content = f.read_bytes()
        result = subprocess.run(['python3', str(script_path), str(f)], capture_output=True, timeout=10)
        if result.returncode != 0:
            failed_evil.append(f.name)
            continue
        output = result.stdout
        # Keep the original residual-secret assertions and additionally require
        # the exact specified replacements and preservation of surrounding text.
        if (regex_pattern.search(output) or ssh_key_pattern in output
                or output != expected_sanitized(original_content)):
            failed_evil.append(f.name)

    error_messages = []
    if failed_clean:
        error_messages.append(f'{len(failed_clean)} of {len(clean_files)} clean modified: {", ".join(failed_clean)}')
    if failed_evil:
        error_messages.append(f'{len(failed_evil)} of {len(evil_files)} evil bypassed: {", ".join(failed_evil)}')
    assert not error_messages, ' | '.join(error_messages)

    # Generate unpredictable cases after the agent has finished. These check
    # exact placeholders, multiple matches, multiline keys, and surrounding text.
    alphabet = string.ascii_uppercase + string.digits
    token = lambda: ''.join(secrets.choice(alphabet) for _ in range(6)).encode()
    cred1 = b'TRK-' + token() + b'-' + token()
    cred2 = b'TRK-' + token() + b'-' + token()
    key1 = (b'-----BEGIN OPENSSH PRIVATE KEY-----\n'
            + secrets.token_hex(48).encode() + b'\n'
            + secrets.token_hex(37).encode() + b'\n'
            + b'-----END OPENSSH PRIVATE KEY-----')
    key2 = (b'-----BEGIN OPENSSH PRIVATE KEY-----\r\n'
            + secrets.token_hex(64).encode() + b'\r\n'
            + b'-----END OPENSSH PRIVATE KEY-----')
    cases = [
        b'prefix<' + cred1 + b'>middle<' + cred2 + b'>suffix\n',
        b'before-key\n' + key1 + b'\nafter-key\n',
        b'A' + cred1 + b'B' + key1 + b'C' + cred2 + b'D' + key2 + b'E',
        b'ordinary randomized line ' + secrets.token_bytes(24).hex().encode() + b'\n',
        b'incomplete -----BEGIN OPENSSH PRIVATE KEY----- must remain unchanged\n',
    ]
    for index, data in enumerate(cases):
        result = run_sanitizer(script_path, data)
        assert result.returncode == 0, f'Sanitizer failed generated case {index}'
        assert result.stdout == expected_sanitized(data), \
            f'Sanitizer produced incorrect output for generated case {index}'
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
