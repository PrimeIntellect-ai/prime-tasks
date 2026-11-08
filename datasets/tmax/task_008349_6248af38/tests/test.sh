#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import base64
import json
import os
import secrets
import shutil
import stat
import subprocess
import sys
import uuid

SCRIPT = '/home/user/audit_procs.py'
DUMPS = '/home/user/proc_dumps'
REPORT = '/home/user/audit_report.json'
KEY_FILE = '/home/user/.ssh/leaked_id_rsa'
CONFIG = '/home/user/.ssh/config'


def run_scanner():
    for path in (REPORT, KEY_FILE, CONFIG):
        try:
            os.unlink(path)
        except FileNotFoundError:
            pass
    result = subprocess.run(
        [sys.executable, SCRIPT],
        cwd='/home/user',
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=15,
    )
    assert result.returncode == 0, (
        f'audit_procs.py exited with {result.returncode}. '
        f'stdout={result.stdout!r}, stderr={result.stderr!r}'
    )


def read_report():
    assert os.path.exists(REPORT), f'Audit report not found at {REPORT}'
    try:
        with open(REPORT, 'r', encoding='utf-8') as f:
            data = json.load(f)
    except json.JSONDecodeError as exc:
        raise AssertionError(f'File {REPORT} does not contain valid JSON: {exc}')
    assert isinstance(data, list), 'Audit report JSON must be a list of dictionaries.'
    return data


def check_report(expected):
    data = read_report()
    assert len(data) == len(expected), (
        f'Expected exactly {len(expected)} entries in the audit report, found {len(data)}.'
    )
    actual_by_pid = {}
    for entry in data:
        assert isinstance(entry, dict), 'Every audit report entry must be a dictionary.'
        assert set(entry.keys()) == {'pid', 'uid', 'leaked_key'}, (
            'Each report entry must contain exactly pid, uid, and leaked_key.'
        )
        assert type(entry['pid']) is int, 'pid must be an integer.'
        assert type(entry['uid']) is int, 'uid must be an integer.'
        assert isinstance(entry['leaked_key'], str), 'leaked_key must be a string.'
        assert entry['pid'] not in actual_by_pid, 'Report contains a duplicate PID.'
        actual_by_pid[entry['pid']] = entry

    assert set(actual_by_pid) == set(expected), (
        f'Expected report PIDs {sorted(expected)}, got {sorted(actual_by_pid)}.'
    )
    for pid, leaked_key in expected.items():
        entry = actual_by_pid[pid]
        assert entry['uid'] == 0, f'Expected uid 0 for PID {pid}, got {entry["uid"]}.'
        assert entry['leaked_key'] == leaked_key, (
            f'The leaked_key for PID {pid} does not match the decoded payload.'
        )


def check_key(expected_key):
    assert os.path.exists(KEY_FILE), f'Leaked SSH key file not found at {KEY_FILE}'
    mode = stat.S_IMODE(os.stat(KEY_FILE).st_mode)
    assert mode == 0o600, f'Permissions for {KEY_FILE} should be 600, got {oct(mode)}'
    with open(KEY_FILE, 'r', encoding='utf-8') as f:
        content = f.read()
    assert content == expected_key, 'The content of leaked_id_rsa is incorrect.'


def parse_host_blocks():
    assert os.path.exists(CONFIG), f'SSH config file not found at {CONFIG}'
    blocks = []
    current = None
    with open(CONFIG, 'r', encoding='utf-8') as f:
        for raw in f:
            line = raw.split('#', 1)[0].strip()
            if not line:
                continue
            parts = line.split()
            keyword = parts[0].lower()
            values = parts[1:]
            if keyword == 'host':
                current = {'patterns': values, 'directives': []}
                blocks.append(current)
            elif current is not None:
                current['directives'].append((keyword, values))
    return blocks


def check_config():
    blocks = parse_host_blocks()
    targets = [
        block for block in blocks
        if any(pattern.lower() == 'audit-target' for pattern in block['patterns'])
    ]
    assert targets, "Host entry 'audit-target' not found in SSH config."

    def block_is_hardened(block):
        directives = block['directives']
        identity = any(
            key == 'identityfile' and values == ['/home/user/.ssh/leaked_id_rsa']
            for key, values in directives
        )
        identities_only = any(
            key == 'identitiesonly' and len(values) == 1 and values[0].lower() == 'yes'
            for key, values in directives
        )
        password_auth = any(
            key == 'passwordauthentication' and len(values) == 1 and values[0].lower() == 'no'
            for key, values in directives
        )
        return identity and identities_only and password_auth

    assert any(block_is_hardened(block) for block in targets), (
        'IdentityFile, IdentitiesOnly yes, and PasswordAuthentication no must all '
        'appear inside the audit-target Host block.'
    )


def expected_original_key():
    with open('/home/user/proc_dumps/202_cmdline', 'rb') as f:
        parts = f.read().split(b'\x00')
    assert b'--auth-token' in parts, 'Original PID 202 dump is missing --auth-token.'
    index = parts.index(b'--auth-token')
    return base64.b64decode(parts[index + 1], validate=True).decode('utf-8')


def write_process(pid, uid, argv):
    encoded = b'\x00'.join(arg.encode('utf-8') for arg in argv) + b'\x00'
    with open(os.path.join(DUMPS, f'{pid}_cmdline'), 'wb') as f:
        f.write(encoded)
    with open(os.path.join(DUMPS, f'{pid}_status'), 'w', encoding='utf-8') as f:
        f.write(
            f'Name:\ttestproc\nState:\tS (sleeping)\n'
            f'Uid:\t{uid}\t{uid}\t{uid}\t{uid}\n'
            f'Gid:\t{uid}\t{uid}\t{uid}\t{uid}\n'
        )


def test_scanner_and_outputs():
    assert os.path.lexists(SCRIPT), f'Process analysis script not found at {SCRIPT}'
    script_stat = os.lstat(SCRIPT)
    assert stat.S_ISREG(script_stat.st_mode), f'{SCRIPT} must be a regular Python script.'

    # Execute the submitted scanner against the original process snapshots.
    original_key = expected_original_key()
    run_scanner()
    original_report = read_report()
    assert len(original_report) == 1, (
        f'Expected exactly 1 entry in the audit report, found {len(original_report)}.'
    )
    assert isinstance(original_report[0], dict), 'Audit report entry must be a dictionary.'
    assert set(original_report[0].keys()) == {'pid', 'uid', 'leaked_key'}, (
        'The report entry must have exactly pid, uid, and leaked_key.'
    )
    assert original_report[0]['pid'] == 202, (
        f'Expected pid 202, got {original_report[0]["pid"]}'
    )
    assert original_report[0]['uid'] == 0, (
        f'Expected uid 0, got {original_report[0]["uid"]}'
    )
    assert original_report[0]['leaked_key'] == original_key, (
        'The leaked_key in the report does not match the decoded payload.'
    )
    check_key(original_key)
    check_config()

    # Replace the snapshots with unpredictable PIDs and payloads, then execute
    # the scanner again. This ensures the artifact actually scans all PID pairs,
    # checks the real UID, parses NUL-delimited argv, and decodes the next argument.
    backup = f'/home/user/proc_dumps.verifier_backup_{uuid.uuid4().hex}'
    root_pid = secrets.randbelow(700000) + 10000
    other_pids = {root_pid}
    while len(other_pids) < 3:
        other_pids.add(secrets.randbelow(700000) + 10000)
    user_pid, no_token_pid = list(other_pids - {root_pid})
    marker = secrets.token_hex(24)
    dynamic_key = (
        '-----BEGIN OPENSSH PRIVATE KEY-----\n'
        + marker
        + '\n-----END OPENSSH PRIVATE KEY-----'
    )
    encoded_key = base64.b64encode(dynamic_key.encode('utf-8')).decode('ascii')
    ignored_key = base64.b64encode(b'not-a-root-secret').decode('ascii')

    os.rename(DUMPS, backup)
    os.mkdir(DUMPS)
    try:
        write_process(
            root_pid,
            0,
            ['/opt/random-daemon', '--mode', 'audit', '--auth-token', encoded_key, '--verbose'],
        )
        write_process(
            user_pid,
            1000,
            ['/opt/user-daemon', '--auth-token', ignored_key],
        )
        write_process(no_token_pid, 0, ['/opt/root-daemon', '--verbose'])

        run_scanner()
        check_report({root_pid: dynamic_key})
        check_key(dynamic_key)
        check_config()
    finally:
        if os.path.isdir(DUMPS):
            shutil.rmtree(DUMPS)
        os.rename(backup, DUMPS)

    # Restore outputs corresponding to the original supplied snapshots.
    run_scanner()
    check_report({202: original_key})
    check_key(original_key)
    check_config()
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
