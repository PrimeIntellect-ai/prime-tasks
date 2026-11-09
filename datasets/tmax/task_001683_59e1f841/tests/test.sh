#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import stat
import secrets
import string
import subprocess
import tempfile

INCIDENT_DIR = '/home/user/incident'
ERROR_OUTPUT = 'Location: https://safe.example.com/error\n\n'
SAFE_PREFIX = 'https://safe.example.com/'


def run_redirect(binary_path, args):
    result = subprocess.run(
        [binary_path, *args],
        capture_output=True,
        text=True,
        timeout=5,
    )
    return result.stdout


def test_binary_analysis_and_authorized_keys_safe():
    """Derive the malicious domain from the ELF and verify the cleaned key file."""
    login_path = os.path.join(INCIDENT_DIR, 'login.cgi')
    original_path = os.path.join(INCIDENT_DIR, 'authorized_keys')
    safe_path = os.path.join(INCIDENT_DIR, 'authorized_keys.safe')

    assert os.path.isfile(login_path), f'The file {login_path} is missing.'
    with open(login_path, 'rb') as f:
        login_data = f.read()
    assert login_data.startswith(b'\x7fELF'), f'{login_path} is not an ELF binary.'

    matches = re.findall(rb'http://([A-Za-z0-9.-]+)/steal\?token=', login_data)
    assert matches, 'The malicious redirect URL was not identified in login.cgi.'
    domains = {match.decode('ascii') for match in matches}
    assert domains == {'evil-empire.xyz'}, 'The exact malicious domain was not correctly identified from login.cgi.'
    malicious_domain = next(iter(domains))

    assert os.path.isfile(safe_path), f'The file {safe_path} is missing.'

    with open(original_path, 'r') as f:
        original_lines = f.read().splitlines()

    with open(safe_path, 'r') as f:
        safe_lines = f.read().splitlines()

    # Preserve the original verifier's expected cleaning assertion.
    expected_lines = [line for line in original_lines if 'evil-empire.xyz' not in line]
    assert len(safe_lines) == len(expected_lines), f'{safe_path} should have {len(expected_lines)} lines, but has {len(safe_lines)}.'
    assert safe_lines == expected_lines, f'The contents of {safe_path} do not match the expected cleaned keys (order must be preserved).'

    # Also independently tie the cleaning operation to the domain extracted above.
    derived_expected_lines = [line for line in original_lines if malicious_domain not in line]
    assert safe_lines == derived_expected_lines
    assert all(malicious_domain not in line for line in safe_lines)


def test_safe_redirect_source_binary_and_functionality():
    """Require C source, a GCC-built ELF, and generalized redirect behavior."""
    source_path = os.path.join(INCIDENT_DIR, 'safe_redirect.c')
    binary_path = os.path.join(INCIDENT_DIR, 'safe_redirect')

    assert os.path.isfile(source_path), f'The source file {source_path} is missing.'
    assert stat.S_ISREG(os.lstat(source_path).st_mode), f'{source_path} must be a regular file.'
    assert os.path.isfile(binary_path), f'The executable {binary_path} is missing.'
    assert stat.S_ISREG(os.lstat(binary_path).st_mode), f'{binary_path} must be a regular file.'
    assert os.access(binary_path, os.X_OK), f'The file {binary_path} is not executable.'

    with open(binary_path, 'rb') as f:
        assert f.read(4) == b'\x7fELF', f'{binary_path} is not an ELF executable.'

    comment = subprocess.run(
        ['readelf', '-p', '.comment', binary_path],
        capture_output=True,
        text=True,
        timeout=5,
    )
    assert comment.returncode == 0 and 'GCC:' in comment.stdout, 'safe_redirect does not contain GCC compiler identification.'

    # Confirm that the submitted C source itself builds successfully with gcc.
    with tempfile.TemporaryDirectory() as tmpdir:
        rebuilt_path = os.path.join(tmpdir, 'safe_redirect.rebuilt')
        build = subprocess.run(
            ['gcc', source_path, '-o', rebuilt_path],
            capture_output=True,
            text=True,
            timeout=15,
        )
        assert build.returncode == 0, f'safe_redirect.c does not compile with gcc: {build.stderr}'

        # Keep all original fixed behavior checks.
        valid_url = 'https://safe.example.com/dashboard'
        assert run_redirect(binary_path, [valid_url]) == f'Location: {valid_url}\n\n', 'safe_redirect did not output correctly for a valid URL.'

        invalid_url = 'http://evil-empire.xyz/steal'
        assert run_redirect(binary_path, [invalid_url]) == ERROR_OUTPUT, 'safe_redirect did not output correctly for an invalid URL.'
        assert run_redirect(binary_path, []) == ERROR_OUTPUT, 'safe_redirect did not output correctly when no arguments were provided.'

        alphabet = string.ascii_letters + string.digits
        nonce = ''.join(secrets.choice(alphabet) for _ in range(24))
        valid_urls = [
            SAFE_PREFIX,
            SAFE_PREFIX + nonce,
            SAFE_PREFIX + 'path/' + nonce + '?next=' + nonce,
        ]
        invalid_urls = [
            'http://safe.example.com/' + nonce,
            'HTTPS://safe.example.com/' + nonce,
            'https://safe.example.com.evil/' + nonce,
            'https://safe.example.com' + nonce,
            ' https://safe.example.com/' + nonce,
            'https://SAFE.example.com/' + nonce,
            nonce,
        ]

        # Exercise both the submitted ELF and a fresh gcc build from the source.
        for executable in (binary_path, rebuilt_path):
            for url in valid_urls:
                assert run_redirect(executable, [url]) == f'Location: {url}\n\n', f'{executable} rejected a valid URL.'
            for url in invalid_urls:
                assert run_redirect(executable, [url]) == ERROR_OUTPUT, f'{executable} accepted an invalid URL.'

            # Exactly one argument is required, even when the first argument is valid.
            assert run_redirect(executable, [valid_urls[1], nonce]) == ERROR_OUTPUT, f'{executable} did not reject extra arguments.'
            assert run_redirect(executable, [nonce, valid_urls[1]]) == ERROR_OUTPUT, f'{executable} did not reject extra arguments.'
            assert run_redirect(executable, ['', nonce]) == ERROR_OUTPUT, f'{executable} did not reject extra arguments.'


def test_csp_txt():
    """Test that csp.txt contains the correct Content Security Policy."""
    csp_path = os.path.join(INCIDENT_DIR, 'csp.txt')
    assert os.path.isfile(csp_path), f'The file {csp_path} is missing.'

    with open(csp_path, 'r') as f:
        content = f.read().strip()

    expected_csp = "Content-Security-Policy: default-src 'self'; script-src 'self'; object-src 'none'; base-uri 'none';"
    assert content == expected_csp, f'The content of {csp_path} is incorrect.'
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
