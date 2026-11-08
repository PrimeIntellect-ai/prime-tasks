#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import hashlib
import json
import os
import pathlib
import pwd
import secrets
import shutil
import stat
import subprocess

SCRIPT_PATH = pathlib.Path('/home/user/analyze.py')
OUTPUT_PATH = pathlib.Path('/home/user/malware_output.txt')
EXPECTED_FLAG = 'EVIDENCE_FLAG: Network isolated successfully. Executing safe local payload.'


def _find_anomalous_file():
    manifest = {
        line.strip().split()[0]
        for line in pathlib.Path('/home/user/manifest.txt').read_text().splitlines()
        if line.strip()
    }
    anomalous = []
    for base in ('/home/user/uploads', '/home/user/system_cache'):
        for path in pathlib.Path(base).rglob('*'):
            if path.is_file():
                digest = hashlib.sha256(path.read_bytes()).hexdigest()
                if digest not in manifest:
                    anomalous.append(path)
    assert len(anomalous) == 1, f'Expected exactly one anomalous file, found: {anomalous}'
    return anomalous[0]


def test_script_uses_subprocess():
    assert SCRIPT_PATH.is_file(), f'The analysis script was not found at {SCRIPT_PATH}.'
    tree = ast.parse(SCRIPT_PATH.read_text(), filename=str(SCRIPT_PATH))
    module_aliases = set()
    callable_aliases = set()
    supported = {'run', 'Popen', 'check_output', 'check_call', 'call'}

    for node in ast.walk(tree):
        if isinstance(node, ast.Import):
            for item in node.names:
                if item.name == 'subprocess':
                    module_aliases.add(item.asname or item.name)
        elif isinstance(node, ast.ImportFrom) and node.module == 'subprocess':
            for item in node.names:
                if item.name in supported:
                    callable_aliases.add(item.asname or item.name)

    used = False
    for node in ast.walk(tree):
        if not isinstance(node, ast.Call):
            continue
        if isinstance(node.func, ast.Name) and node.func.id in callable_aliases:
            used = True
        elif (
            isinstance(node.func, ast.Attribute)
            and node.func.attr in supported
            and isinstance(node.func.value, ast.Name)
            and node.func.value.id in module_aliases
        ):
            used = True

    assert used, 'analyze.py must execute the payload through the subprocess module.'


def test_analyze_executes_derived_payload_with_required_bwrap_policy():
    anomalous = _find_anomalous_file()
    nonce = secrets.token_hex(24)
    expected = (EXPECTED_FLAG + '\nVERIFIER_NONCE:' + nonce + '\n').encode()

    original_payload = anomalous.read_bytes()
    payload_stat = anomalous.stat()
    bwrap_path = pathlib.Path(shutil.which('bwrap') or '/usr/bin/bwrap')
    assert bwrap_path.exists(), 'Bubblewrap is not installed.'
    backup_path = bwrap_path.with_name(bwrap_path.name + '.verifier-backup-' + secrets.token_hex(8))
    log_path = pathlib.Path('/tmp/verifier-bwrap-args.json')

    canary = (
        "print(" + repr(EXPECTED_FLAG) + ")\n"
        "print(" + repr('VERIFIER_NONCE:' + nonce) + ")\n"
    ).encode()

    shim = f'''#!/usr/bin/python3
import json
import os
import subprocess
import sys
args = sys.argv[1:]
with open({str(log_path)!r}, 'w') as f:
    json.dump(args, f)
target = {str(anomalous.resolve())!r}
found = False
for arg in args:
    candidate = arg if os.path.isabs(arg) else os.path.join('/home/user', arg)
    if os.path.realpath(candidate) == target:
        found = True
        break
if not found:
    sys.exit(97)
result = subprocess.run(['/usr/bin/python3', target], stdout=subprocess.PIPE, stderr=subprocess.PIPE)
sys.stdout.buffer.write(result.stdout)
sys.stderr.buffer.write(result.stderr)
sys.exit(result.returncode)
'''

    try:
        anomalous.write_bytes(canary)
        os.chmod(anomalous, stat.S_IMODE(payload_stat.st_mode))
        os.chown(anomalous, payload_stat.st_uid, payload_stat.st_gid)
        log_path.unlink(missing_ok=True)
        OUTPUT_PATH.unlink(missing_ok=True)

        bwrap_path.rename(backup_path)
        bwrap_path.write_text(shim)
        os.chmod(bwrap_path, 0o755)

        user = pwd.getpwnam('user')
        result = subprocess.run(
            ['runuser', '-u', 'user', '--', '/usr/bin/env',
             'HOME=/home/user', 'PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin',
             '/usr/bin/python3', str(SCRIPT_PATH)],
            cwd='/home/user', stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=20
        )
        assert result.returncode == 0, (
            f'analyze.py failed with exit code {result.returncode}.\n'
            f'stdout: {result.stdout.decode(errors="replace")}\n'
            f'stderr: {result.stderr.decode(errors="replace")}'
        )
        assert log_path.is_file(), 'analyze.py did not invoke bwrap.'
        args = json.loads(log_path.read_text())

        assert '--unshare-net' in args, 'bwrap invocation is missing --unshare-net.'
        assert any(args[i:i+3] == ['--ro-bind', '/', '/'] for i in range(len(args) - 2)), \
            'bwrap invocation is missing --ro-bind / /.'
        assert any(args[i:i+2] == ['--proc', '/proc'] for i in range(len(args) - 1)), \
            'bwrap invocation is missing --proc /proc.'
        assert any(args[i:i+2] == ['--dev', '/dev'] for i in range(len(args) - 1)), \
            'bwrap invocation is missing --dev /dev.'

        target_indexes = []
        for i, arg in enumerate(args):
            candidate = arg if os.path.isabs(arg) else os.path.join('/home/user', arg)
            if os.path.realpath(candidate) == str(anomalous.resolve()):
                target_indexes.append(i)
        assert target_indexes, 'bwrap was not asked to execute the anomalous file derived from the manifest.'
        assert any(i > 0 and os.path.basename(args[i-1]).startswith('python') for i in target_indexes), \
            'The anomalous Python file was not passed to a Python interpreter inside bwrap.'

        assert OUTPUT_PATH.is_file(), f'The malware output file was not found at {OUTPUT_PATH}.'
        assert OUTPUT_PATH.read_bytes() == expected, \
            'malware_output.txt must contain exactly the stdout captured from the sandboxed payload.'
    finally:
        if bwrap_path.exists():
            bwrap_path.unlink()
        if backup_path.exists():
            backup_path.rename(bwrap_path)
        anomalous.write_bytes(original_payload)
        os.chmod(anomalous, stat.S_IMODE(payload_stat.st_mode))
        os.chown(anomalous, payload_stat.st_uid, payload_stat.st_gid)


def test_analyze_script_exists():
    """Verify that the analyze.py script was created."""
    script_path = '/home/user/analyze.py'
    assert os.path.isfile(script_path), f'The analysis script was not found at {script_path}.'


def test_malware_output_exists():
    """Verify that the malware output file was created."""
    output_path = '/home/user/malware_output.txt'
    assert os.path.isfile(output_path), f'The malware output file was not found at {output_path}.'


def test_malware_output_content():
    """Verify that the malware output contains the expected sandboxed execution result."""
    output_path = '/home/user/malware_output.txt'
    assert os.path.isfile(output_path), 'Cannot check content because output file does not exist.'
    with open(output_path, 'r') as f:
        content = f.read().strip()
    expected_string = EXPECTED_FLAG
    assert expected_string in content, (
        f'The output file does not contain the expected evidence flag.\n'
        f'Expected to find: {expected_string!r}\nActual content: {content!r}'
    )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
