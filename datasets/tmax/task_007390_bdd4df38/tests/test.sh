#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import hashlib
import json
import os
import secrets
import stat
import subprocess
from pathlib import Path

import pytest

HOME = Path('/home/user')
REPORT = HOME / 'report.txt'
INPUT_PATHS = [HOME / 'server.log', HOME / 'shadow.txt', HOME / 'wordlist.txt']


def go_env():
    env = os.environ.copy()
    env.update({
        'GO111MODULE': 'off',
        'GOPROXY': 'off',
        'GOENV': 'off',
        'CGO_ENABLED': '0',
        'GOCACHE': '/tmp/verifier-gocache',
        'GOPATH': '/tmp/verifier-gopath',
        'HOME': '/tmp/verifier-go-home',
    })
    for path in ('/tmp/verifier-gocache', '/tmp/verifier-gopath', '/tmp/verifier-go-home'):
        os.makedirs(path, exist_ok=True)
    return env


def candidate_programs():
    groups = {}
    for root, dirs, files in os.walk(HOME):
        dirs[:] = [d for d in dirs if d not in {'.cache', 'pkg', 'bin'}]
        sources = []
        for name in files:
            if not name.endswith('.go') or name.endswith('_test.go'):
                continue
            path = Path(root) / name
            if stat.S_ISREG(path.lstat().st_mode) and not path.is_symlink():
                sources.append(str(path))
        if sources:
            groups[root] = sorted(sources)
    preferred = str(HOME)
    return [groups[preferred]] + [groups[k] for k in sorted(groups) if k != preferred] if preferred in groups else [groups[k] for k in sorted(groups)]


def uses_only_standard_library(sources):
    template = '{{if and (not .Standard) (ne .ImportPath "command-line-arguments")}}{{.ImportPath}}{{end}}'
    result = subprocess.run(
        ['go', 'list', '-deps', '-f', template, *sources],
        cwd=str(Path(sources[0]).parent), env=go_env(), text=True,
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=30,
    )
    if result.returncode != 0:
        return False
    return not any(line.strip() for line in result.stdout.splitlines())


def run_program(sources):
    if REPORT.exists() or REPORT.is_symlink():
        REPORT.unlink()
    return subprocess.run(
        ['go', 'run', *sources], cwd=str(Path(sources[0]).parent), env=go_env(),
        text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=30,
    )


def read_report():
    assert os.path.isfile(REPORT), f'Report file {REPORT} does not exist.'
    with open(REPORT, 'r') as f:
        return [line.strip() for line in f.read().strip().splitlines()]


def write_case(ip, session_id, password):
    entries = [
        {'time': '2024-05-01T10:00:00Z', 'ip': '10.20.30.40', 'method': 'GET', 'path': '/index.html', 'status': 200, 'session_id': 'ordinary'},
        {'time': '2024-05-01T10:01:00Z', 'ip': ip, 'method': 'GET', 'path': '/admin/secret_config.json', 'status': 403, 'session_id': 'wrong-salt'},
        {'time': '2024-05-01T10:02:00Z', 'ip': '172.20.0.9', 'method': 'GET', 'path': '/admin/other.json', 'status': 200, 'session_id': 'decoy'},
        {'time': '2024-05-01T10:03:00Z', 'ip': ip, 'method': 'GET', 'path': '/admin/secret_config.json', 'status': 200, 'session_id': session_id},
        {'time': '2024-05-01T10:04:00Z', 'ip': '203.0.113.8', 'method': 'GET', 'path': '/contact', 'status': 200, 'session_id': 'other'},
    ]
    # Vary line ordering so the answer cannot be selected by a fixed line number.
    if secrets.randbits(1):
        entries = [entries[2], entries[0], entries[4], entries[1], entries[3]]
    (HOME / 'server.log').write_text('\n'.join(json.dumps(e) for e in entries) + '\n')

    digest = hashlib.sha256((session_id + password).encode()).hexdigest()
    (HOME / 'shadow.txt').write_text(f'admin:{digest}\n')
    words = ['notit-' + secrets.token_hex(3), 'guest-' + secrets.token_hex(3), password,
             'decoy-' + secrets.token_hex(3), 'last-' + secrets.token_hex(3)]
    if secrets.randbits(1):
        words.reverse()
    (HOME / 'wordlist.txt').write_text('\n'.join(words) + '\n')


def test_report_exists_and_correct_and_is_generated_by_go():
    originals = {path: path.read_bytes() for path in INPUT_PATHS}
    programs = candidate_programs()
    assert programs, 'No Go source program was found under /home/user.'

    selected = None
    try:
        # Find a standard-library-only Go program that regenerates the required
        # report from the original supplied evidence. Existing report contents
        # are deleted before every execution.
        for sources in programs:
            if not uses_only_standard_library(sources):
                continue
            try:
                result = run_program(sources)
            except subprocess.TimeoutExpired:
                continue
            if result.returncode != 0 or not REPORT.is_file():
                continue
            lines = read_report()
            if lines == ['Attacker IP: 192.168.1.105', 'Cracked Password: cyberdragon']:
                selected = sources
                break

        assert selected is not None, 'No standard-library Go program generated the correct report.'

        # Preserve the original verifier's exact report assertions.
        report_path = '/home/user/report.txt'
        assert os.path.isfile(report_path), f'Report file {report_path} does not exist.'
        with open(report_path, 'r') as f:
            lines = [line.strip() for line in f.read().strip().splitlines()]
        assert len(lines) == 2, f'Expected exactly 2 lines in {report_path}, but got {len(lines)}.'
        expected_ip_line = 'Attacker IP: 192.168.1.105'
        expected_password_line = 'Cracked Password: cyberdragon'
        assert lines[0] == expected_ip_line, f"First line is incorrect. Expected '{expected_ip_line}', got '{lines[0]}'."
        assert lines[1] == expected_password_line, f"Second line is incorrect. Expected '{expected_password_line}', got '{lines[1]}'."

        # Exercise the same Go artifact on unpredictable evidence and derive
        # each expected password hash inside the verifier.
        for _ in range(2):
            ip = f'198.51.100.{secrets.randbelow(200) + 20}'
            session_id = 'salt-' + secrets.token_hex(10)
            password = 'pw-' + secrets.token_hex(9)
            write_case(ip, session_id, password)
            result = run_program(selected)
            assert result.returncode == 0, f'Go program failed: {result.stderr}'
            lines = read_report()
            assert len(lines) == 2, f'Expected exactly 2 report lines, got {len(lines)}.'
            assert lines[0] == f'Attacker IP: {ip}'
            assert lines[1] == f'Cracked Password: {password}'
    finally:
        for path, data in originals.items():
            path.write_bytes(data)

    # Leave and re-check the requested report for the original supplied inputs.
    result = run_program(selected)
    assert result.returncode == 0, f'Go program failed on original inputs: {result.stderr}'
    lines = read_report()
    assert lines == ['Attacker IP: 192.168.1.105', 'Cracked Password: cyberdragon']
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
