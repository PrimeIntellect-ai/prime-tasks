#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import importlib.util
import json
import os
import re
import shlex
import uuid
from pathlib import Path

import pytest


def test_report_json():
    report_path = '/home/user/evidence/report.json'
    assert os.path.isfile(report_path), f"Report file {report_path} is missing."

    with open(report_path, 'r') as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"Report file {report_path} does not contain valid JSON.")

    assert "cwe_id" in data, "Report JSON is missing the 'cwe_id' key."
    assert data["cwe_id"].upper() == "CWE-601", f"Incorrect CWE ID. Expected CWE-601, got {data['cwe_id']}."

    assert "c2_ip" in data, "Report JSON is missing the 'c2_ip' key."
    assert data["c2_ip"] == "203.0.113.85", f"Incorrect C2 IP. Expected 203.0.113.85, got {data['c2_ip']}."


def _firewall_argv(content):
    # Permit comments, a shebang, blank lines, and shell line continuations, but
    # require the executable portion of the file to be one simple command.
    logical = re.sub(r'\\\r?\n', ' ', content)
    command_lines = [
        line for line in logical.splitlines()
        if line.strip() and not line.lstrip().startswith('#')
    ]
    assert len(command_lines) == 1, (
        "block_c2.sh must contain exactly one executable command."
    )

    lexer = shlex.shlex(command_lines[0], posix=True, punctuation_chars=';&|<>()')
    lexer.whitespace_split = True
    lexer.commenters = '#'
    argv = list(lexer)
    assert argv, "block_c2.sh does not contain an executable command."
    assert not any(token in {';', ';;', '&', '&&', '|', '||', '<', '>', '(', ')'} for token in argv), (
        "Shell operators and additional commands are not allowed in block_c2.sh."
    )
    return argv


def test_block_c2_sh():
    script_path = '/home/user/evidence/block_c2.sh'
    assert os.path.isfile(script_path), f"Firewall script {script_path} is missing."

    with open(script_path, 'r') as f:
        content = f.read().strip()

    # Preserve the original component checks.
    normalized_content = re.sub(r'\s+', ' ', content)
    assert "iptables" in normalized_content, "The script does not contain an 'iptables' command."
    assert "-A OUTPUT" in normalized_content or "--append OUTPUT" in normalized_content, "The rule must append to the OUTPUT chain."
    assert "-d 203.0.113.85" in normalized_content or "--destination 203.0.113.85" in normalized_content, "The rule must specify the correct destination IP."
    assert "-p tcp" in normalized_content or "--protocol tcp" in normalized_content, "The rule must specify the TCP protocol."
    assert "--dport 4444" in normalized_content or "--destination-port 4444" in normalized_content, "The rule must specify destination port 4444."
    assert "-j DROP" in normalized_content or "--jump DROP" in normalized_content, "The rule must DROP the traffic."

    argv = _firewall_argv(content)
    assert Path(argv[0]).name == 'iptables', "The sole command must be iptables."

    aliases = {
        '-A': 'chain', '--append': 'chain',
        '-d': 'destination', '--destination': 'destination',
        '-p': 'protocol', '--protocol': 'protocol',
        '--dport': 'port', '--destination-port': 'port',
        '-j': 'jump', '--jump': 'jump',
    }
    expected = {
        'chain': 'OUTPUT',
        'destination': '203.0.113.85',
        'protocol': 'tcp',
        'port': '4444',
        'jump': 'DROP',
    }

    assert len(argv[1:]) == 10, "The iptables command contains missing or extra arguments."
    seen = {}
    for index in range(1, len(argv), 2):
        option = argv[index]
        assert option in aliases, f"Unexpected iptables option or argument: {option}"
        key = aliases[option]
        assert key not in seen, f"Duplicate iptables setting: {option}"
        seen[key] = argv[index + 1]

    assert seen == expected, f"Incorrect iptables rule settings: {seen}"


def _load_application():
    app_path = '/home/user/webapp/app.py'
    spec = importlib.util.spec_from_file_location('submitted_webapp_' + uuid.uuid4().hex, app_path)
    assert spec is not None and spec.loader is not None, "Could not load app.py."
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    assert hasattr(module, 'app'), "app.py does not define a Flask application named 'app'."
    return module.app


def test_app_py_patched():
    app_path = '/home/user/webapp/app.py'
    assert os.path.isfile(app_path), f"Application file {app_path} is missing."

    with open(app_path, 'r') as f:
        content = f.read()

    # Preserve the original source assertions.
    has_slash_check = "startswith('/')" in content or 'startswith("/")' in content or "next_url[0] == '/'" in content or 'next_url[0] == "/"' in content
    has_double_slash_check = "startswith('//')" in content or 'startswith("//")' in content or "http" in content or "://" in content
    assert has_slash_check, "app.py does not appear to check if next_url starts with '/'."
    assert has_double_slash_check, "app.py does not appear to check against absolute URLs (e.g., '//' or 'http')."
    assert "redirect(" in content, "app.py is missing redirect logic."

    # Execute the submitted Flask application and verify the login behavior.
    app = _load_application()
    app.config.update(TESTING=True)
    client = app.test_client()
    token = uuid.uuid4().hex

    valid_paths = [
        '/' + token,
        '/' + token + '?source=login',
        '/http/' + token,
    ]
    for target in valid_paths:
        response = client.post('/login', data={'next': target})
        assert response.status_code in (301, 302, 303, 307, 308), f"Valid relative path {target!r} did not redirect."
        assert response.headers.get('Location') == target, f"Valid relative path {target!r} was not followed."

    invalid_targets = [
        '//' + token + '.example/path',
        'http://' + token + '.example/path',
        'https://' + token + '.example/path',
        token + '/relative-without-leading-slash',
    ]
    for target in invalid_targets:
        response = client.post('/login', data={'next': target})
        assert response.status_code in (301, 302, 303, 307, 308), f"Invalid target {target!r} did not redirect to the fallback."
        assert response.headers.get('Location') == '/dashboard', f"Invalid target {target!r} was not rejected."

    for data in ({}, {'next': ''}):
        response = client.post('/login', data=data)
        assert response.headers.get('Location') == '/dashboard', "Missing or empty next parameter must redirect to /dashboard."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
