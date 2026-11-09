#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import secrets
import subprocess
import tempfile

SOURCE = '/home/user/auth_cgi.c'
BINARY = '/home/user/auth_cgi'


def run_cgi(query):
    env = os.environ.copy()
    env['QUERY_STRING'] = query
    return subprocess.run(
        [BINARY], env=env, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
        text=True, timeout=5
    )


def test_redacted_requests_log():
    original_log = '/home/user/auth_requests.log'
    redacted_log = '/home/user/redacted_requests.log'

    assert os.path.isfile(original_log), f"Original log file {original_log} is missing."
    assert os.path.isfile(redacted_log), f"Redacted log file {redacted_log} is missing."

    with open(original_log, 'r') as f:
        original_lines = f.read().splitlines()
    with open(redacted_log, 'r') as f:
        redacted_lines = f.read().splitlines()

    assert len(original_lines) == len(redacted_lines), "Redacted log does not have the same number of lines as the original log."

    for orig, red in zip(original_lines, redacted_lines):
        match = re.search(r'pwd=([^&\s]+)', orig)
        if match:
            orig_pwd = match.group(1)
            assert orig_pwd not in red, f"Original password '{orig_pwd}' was not redacted in line: {red}"

        assert "pwd=[REDACTED]" in red, f"Expected 'pwd=[REDACTED]' not found in line: {red}"
        orig_stripped = re.sub(r'pwd=[^&\s]+', '', orig)
        red_stripped = re.sub(r'pwd=\[REDACTED\]', '', red)
        assert orig_stripped == red_stripped, f"Other parts of the line were modified. Original (stripped): {orig_stripped}, Redacted (stripped): {red_stripped}"


def test_compilation():
    assert os.path.isfile(SOURCE), f"Source file {SOURCE} is missing."
    assert os.path.isfile(BINARY), f"Compiled binary {BINARY} is missing."
    assert os.access(BINARY, os.X_OK), f"Compiled binary {BINARY} is not executable."

    with open(BINARY, 'rb') as f:
        assert f.read(4) == b'\x7fELF', "auth_cgi is not a compiled ELF binary."

    fd, rebuilt = tempfile.mkstemp(prefix='auth_cgi_rebuilt_')
    os.close(fd)
    try:
        result = subprocess.run(
            ['gcc', SOURCE, '-o', rebuilt], stdout=subprocess.PIPE,
            stderr=subprocess.PIPE, text=True, timeout=20
        )
        assert result.returncode == 0, f"Patched source does not compile with gcc: {result.stderr}"
        with open(BINARY, 'rb') as f:
            installed_bytes = f.read()
        with open(rebuilt, 'rb') as f:
            rebuilt_bytes = f.read()
        assert installed_bytes == rebuilt_bytes, "auth_cgi was not compiled from the current patched auth_cgi.c using gcc without special flags."
    finally:
        if os.path.exists(rebuilt):
            os.remove(rebuilt)

    symbols = subprocess.run(
        ['nm', '-D', BINARY], stdout=subprocess.PIPE, stderr=subprocess.PIPE,
        text=True, timeout=5, check=True
    ).stdout
    for function in ('fopen', 'fprintf', 'fclose'):
        assert re.search(r'\b' + function + r'(@|\b)', symbols), f"Compiled CGI does not use required {function} file I/O."
    assert not re.search(r'\bsystem(@|\b)', symbols), "Compiled CGI still references system()."


def test_command_injection_fix():
    access_log = '/home/user/access.log'
    token = secrets.token_hex(4)
    hacked_file = '/tmp/hk' + token
    injected_user = "hacker';touch${IFS}" + hacked_file + ";#"

    for path in (access_log, hacked_file):
        if os.path.exists(path):
            os.remove(path)

    result = run_cgi('user=' + injected_user + '&redirect=https://evil.example')
    assert result.returncode == 0, f"CGI execution failed: {result.stderr}"
    assert not os.path.exists(hacked_file), f"Command injection vulnerability still exists: {hacked_file} was created."
    assert os.path.isfile(access_log), f"Access log {access_log} was not created."

    with open(access_log, 'r') as f:
        content = f.read()
    assert content == 'Access by ' + injected_user + '\n', "Access log did not contain the exact username parsed from the query."


def test_open_redirect_fix():
    token = secrets.token_hex(8)
    invalid_redirects = [
        'https://' + token + '.example/path',
        'http://' + token + '.example/path',
        '//' + token + '.example/path',
        token + '.example/path',
        'javascript:' + token,
    ]

    for redirect in invalid_redirects:
        result = run_cgi('user=admin&redirect=' + redirect)
        assert result.returncode == 0, f"CGI execution failed for redirect {redirect}: {result.stderr}"
        assert 'Location:' not in result.stdout, f"Open redirect vulnerability still exists: Location header allowed {redirect!r}."

    safe_redirects = ['/safe-' + token, '/account/' + token]
    for redirect in safe_redirects:
        result = run_cgi('user=admin&redirect=' + redirect)
        assert result.returncode == 0, f"CGI execution failed for redirect {redirect}: {result.stderr}"
        assert 'Location: ' + redirect in result.stdout, f"Safe redirect to {redirect!r} was improperly blocked."


def test_csp_header():
    redirect = '/safe-' + secrets.token_hex(6)
    result = run_cgi('user=admin&redirect=' + redirect)
    assert result.returncode == 0, f"CGI execution failed: {result.stderr}"

    csp = "Content-Security-Policy: default-src 'self';"
    assert csp in result.stdout, "Content-Security-Policy header is missing or incorrect."
    assert '\n\n' in result.stdout, "CGI output has no blank line separating headers from the body."
    header_section = result.stdout.split('\n\n', 1)[0]
    assert csp in header_section, "Content-Security-Policy header must be in the HTTP headers section (before the blank line)."
    assert header_section.splitlines()[-1] == csp, "Content-Security-Policy header must appear immediately before the header/body blank line."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
