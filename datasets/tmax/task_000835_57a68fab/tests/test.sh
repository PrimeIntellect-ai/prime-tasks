#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import secrets
import subprocess
import sys
import urllib.parse


def get_expected_ips(log_path):
    ips = set()
    if not os.path.exists(log_path):
        return ips

    with open(log_path, 'r') as f:
        for line in f:
            parts = line.split()
            if len(parts) < 9:
                continue

            ip = parts[0]
            request = parts[6]
            status = parts[8]

            if status != '302':
                continue

            if not request.startswith('/login'):
                continue

            parsed_url = urllib.parse.urlparse(request)
            query_params = urllib.parse.parse_qs(parsed_url.query)

            if 'next' in query_params:
                next_val = query_params['next'][0]
                if next_val.startswith('http://') or next_val.startswith('https://'):
                    ips.add(ip)
    return sorted(list(ips))


def parse_csp(csp_string):
    directives = {}
    parts = csp_string.split(';')
    for part in parts:
        part = part.strip()
        if not part:
            continue
        tokens = part.split(None, 1)
        if tokens:
            name = tokens[0].lower()
            value = tokens[1] if len(tokens) > 1 else ''
            directives[name] = value
    return directives


def test_ssh_deny_conf():
    """Check the originally generated SSH deny configuration."""
    log_path = "/home/user/logs/gateway.log"
    conf_path = "/home/user/ssh_deny.conf"

    assert os.path.isfile(conf_path), f"The file {conf_path} was not created."

    expected_ips = get_expected_ips(log_path)
    expected_lines = [f"DenyUsers *@{ip}" for ip in expected_ips]

    with open(conf_path, 'r') as f:
        actual_lines = [line.strip() for line in f if line.strip()]

    assert actual_lines == expected_lines, (
        f"Contents of {conf_path} do not match expected output.\n"
        f"Expected: {expected_lines}\n"
        f"Actual: {actual_lines}"
    )


def test_hardened_csp_txt():
    """Check the originally generated hardened CSP."""
    orig_csp_path = "/home/user/csp.txt"
    hardened_csp_path = "/home/user/hardened_csp.txt"

    assert os.path.isfile(hardened_csp_path), f"The file {hardened_csp_path} was not created."

    with open(orig_csp_path, 'r') as f:
        orig_csp = f.read().strip()

    expected_directives = parse_csp(orig_csp)
    expected_directives['form-action'] = "'self'"

    with open(hardened_csp_path, 'r') as f:
        hardened_csp = f.read().strip()

    actual_directives = parse_csp(hardened_csp)

    assert actual_directives == expected_directives, (
        f"The CSP in {hardened_csp_path} does not have the correct directives.\n"
        f"Expected directives: {expected_directives}\n"
        f"Actual directives: {actual_directives}"
    )


def run_script(log_text, csp_text, expected_ips):
    script_path = "/home/user/enforce.py"
    log_path = "/home/user/logs/gateway.log"
    csp_path = "/home/user/csp.txt"
    conf_path = "/home/user/ssh_deny.conf"
    hardened_path = "/home/user/hardened_csp.txt"

    assert os.path.isfile(script_path), f"The required Python script {script_path} does not exist."

    with open(log_path, 'w') as f:
        f.write(log_text)
    with open(csp_path, 'w') as f:
        f.write(csp_text)

    for output in (conf_path, hardened_path):
        if os.path.lexists(output):
            os.remove(output)

    result = subprocess.run(
        [sys.executable, script_path],
        cwd="/home/user",
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=15,
    )
    assert result.returncode == 0, (
        f"Running {script_path} failed with exit code {result.returncode}.\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )
    assert os.path.isfile(conf_path), "The script did not create ssh_deny.conf."
    assert os.path.isfile(hardened_path), "The script did not create hardened_csp.txt."

    expected_lines = [f"DenyUsers *@{ip}" for ip in sorted(set(expected_ips))]
    with open(conf_path, 'r') as f:
        actual_lines = f.read().splitlines()
    assert actual_lines == expected_lines, (
        f"Dynamic SSH output was incorrect. Expected {expected_lines}, got {actual_lines}."
    )

    expected_directives = parse_csp(csp_text.strip())
    expected_directives['form-action'] = "'self'"
    with open(hardened_path, 'r') as f:
        actual_directives = parse_csp(f.read().strip())
    assert actual_directives == expected_directives, (
        f"Dynamic CSP output was incorrect. Expected {expected_directives}, got {actual_directives}."
    )


def test_enforce_script_on_unseen_inputs():
    token = secrets.token_hex(6)
    ip_a = f"10.41.7.{secrets.randbelow(150) + 1}"
    ip_b = f"172.27.9.{secrets.randbelow(150) + 1}"
    ip_safe = f"192.0.2.{secrets.randbelow(150) + 1}"
    absolute_encoded = urllib.parse.quote(f"https://{token}.example/collect", safe='')

    first_log = "\n".join([
        f'{ip_b} - - [11/Sep/2026:10:00:00 +0000] "GET /login?source=x&next={absolute_encoded} HTTP/1.1" 302 12',
        f'{ip_safe} - - [11/Sep/2026:10:00:01 +0000] "GET /login?next=/dashboard HTTP/1.1" 302 12',
        f'{ip_a} - - [11/Sep/2026:10:00:02 +0000] "POST /login?next=http://{token}.invalid/path HTTP/1.1" 302 12',
        f'{ip_b} - - [11/Sep/2026:10:00:03 +0000] "GET /login?next=https://duplicate.invalid HTTP/1.1" 302 12',
        f'{ip_safe} - - [11/Sep/2026:10:00:04 +0000] "GET /login?next=https://ignored.invalid HTTP/1.1" 200 12',
        f'{ip_safe} - - [11/Sep/2026:10:00:05 +0000] "GET /logout?next=https://ignored.invalid HTTP/1.1" 302 12',
        "",
    ])
    first_csp = f"default-src 'self'; form-action https://{token}.example; object-src 'none'\n"
    run_script(first_log, first_csp, [ip_a, ip_b])

    ip_c = f"198.51.100.{secrets.randbelow(150) + 1}"
    second_log = "\n".join([
        f'{ip_c} - - [11/Sep/2026:11:00:00 +0000] "GET /login?next=https://{token}.test/landing HTTP/1.1" 302 4',
        f'{ip_a} - - [11/Sep/2026:11:00:01 +0000] "GET /login?next=profile HTTP/1.1" 302 4',
        "",
    ])
    second_csp = f"default-src 'self'; script-src 'nonce-{token}'\n"
    run_script(second_log, second_csp, [ip_c])
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
