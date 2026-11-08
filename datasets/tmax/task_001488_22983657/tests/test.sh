#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import base64
import json
import os
import re
import stat
import subprocess
from pathlib import Path

HOME = Path('/home/user')
RAW = HOME / 'raw_logs.json'
CLEAN = HOME / 'clean_logs.json'
FINAL = HOME / 'final_output.log'
SCRIPT = HOME / 'enforce.py'
AUDIT = Path('/var/log/unshare-audit.log')
KEY_RE = re.compile(r'AKIA[A-Z0-9]{16}')


def transform(entries):
    result = []
    for entry in entries:
        decoded = base64.b64decode(entry['b64_payload'], validate=True).decode('utf-8')
        redacted = KEY_RE.sub('[REDACTED]', decoded)
        updated = dict(entry)
        updated['b64_payload'] = base64.b64encode(redacted.encode('utf-8')).decode('ascii')
        result.append(updated)
    return result


def load_json(path):
    with path.open('r', encoding='utf-8') as f:
        return json.load(f)


def test_submission():
    assert SCRIPT.is_file(), f'The file {SCRIPT} does not exist.'
    assert stat.S_ISREG(SCRIPT.stat().st_mode), f'{SCRIPT} is not a regular file.'

    original_entries = load_json(RAW)
    expected_data = transform(original_entries)

    # Preserve the original verifier's assertions, with expectations derived
    # from the stated regex rather than an incorrect hardcoded payload.
    assert CLEAN.is_file(), f'The file {CLEAN} does not exist.'
    assert load_json(CLEAN) == expected_data, \
        f'The contents of {CLEAN} do not match the expected redacted state.'

    assert FINAL.is_file(), f'The file {FINAL} does not exist.'
    assert load_json(FINAL) == expected_data, \
        f'The contents of {FINAL} do not match the expected redacted state.'

    # The setup's protected wrapper records successful unshare invocations and
    # the resulting final file identity. Require the invocation which produced
    # the submitted final output to use both user and network namespaces.
    assert AUDIT.is_file(), 'No successful audited unshare invocation was recorded.'
    final_stat = FINAL.stat()
    matching_invocation = False
    for line in AUDIT.read_text(encoding='utf-8').splitlines():
        fields = line.split('\t')
        if len(fields) < 8:
            continue
        try:
            status, dev, ino, size, msec, mnsec, argc = map(int, fields[:7])
            args = [bytes.fromhex(value).decode('utf-8') for value in fields[7:]]
        except (ValueError, UnicodeDecodeError):
            continue
        if status != 0 or argc != len(args):
            continue
        if (dev, ino, size, msec, mnsec) != (
            final_stat.st_dev, final_stat.st_ino, final_stat.st_size,
            final_stat.st_mtime_ns // 1_000_000_000,
            final_stat.st_mtime_ns % 1_000_000_000,
        ):
            continue

        command_args = args[1:]
        has_user = any(a == '--user' or (a.startswith('-') and not a.startswith('--') and 'U' in a[1:]) for a in command_args)
        has_net = any(a == '--net' or (a.startswith('-') and not a.startswith('--') and 'n' in a[1:]) for a in command_args)
        if not (has_user and has_net):
            continue

        idx = 0
        while idx < len(command_args) and command_args[idx].startswith('-'):
            idx += 1
        if idx + 2 >= len(command_args) or os.path.basename(command_args[idx]) != 'bash' or command_args[idx + 1] != '-c':
            continue
        shell_command = command_args[idx + 2]
        if re.fullmatch(r'\s*cat\s+/home/user/clean_logs\.json\s*>\s*/home/user/final_output\.log\s*', shell_command):
            matching_invocation = True
            break

    assert matching_invocation, \
        'final_output.log was not produced by the required user-and-network namespace unshare command.'

    # Execute the submitted artifact on independently derived cases so fixed
    # output files or a hardcoded implementation cannot satisfy the verifier.
    challenge = [
        {'id': 'plain', 'b64_payload': base64.b64encode(b'AKiey must stay unchanged').decode('ascii')},
        {'id': 'one', 'b64_payload': base64.b64encode(b'before AKIAABCDEFGHIJKLMNOP after').decode('ascii')},
        {'id': 'edges', 'b64_payload': base64.b64encode(b'AKIA1234567890ABCDEF / AKIA123 / akiaABCDEFGHIJKLMNOP').decode('ascii')},
        {'id': 'two', 'b64_payload': base64.b64encode(b'AKIAZZZZZZZZZZZZZZZZ+AKIA0000000000000000').decode('ascii')},
    ]
    expected_challenge = transform(challenge)
    backups = {p: p.read_bytes() if p.exists() else None for p in (RAW, CLEAN, FINAL)}
    try:
        RAW.write_text(json.dumps(challenge), encoding='utf-8')
        if CLEAN.exists():
            CLEAN.unlink()
        subprocess.run(['python3', str(SCRIPT)], cwd=str(HOME), check=True, timeout=20)
        assert RAW.read_text(encoding='utf-8') == json.dumps(challenge), 'enforce.py modified raw_logs.json.'
        assert CLEAN.is_file(), 'enforce.py did not create clean_logs.json when executed.'
        assert load_json(CLEAN) == expected_challenge, 'enforce.py failed independently generated redaction cases.'
    finally:
        for path, content in backups.items():
            if content is None:
                if path.exists():
                    path.unlink()
            else:
                path.write_bytes(content)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
