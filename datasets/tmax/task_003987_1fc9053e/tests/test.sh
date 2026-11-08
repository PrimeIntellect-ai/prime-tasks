#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import json
import os
import shutil
import struct
import subprocess
import sys
import time
import uuid

import pytest

REPORT_PATH = '/home/user/scan_report.json'
SCRIPT_PATH = '/home/user/scan_configs.py'
INCOMING = '/home/user/incoming'


def create_cfgpack(path, entries):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, 'wb') as f:
        f.write(b'CFGP')
        f.write(struct.pack('<H', len(entries)))
        for name, data in entries:
            name_bytes = name.encode('utf-8')
            f.write(struct.pack('<H', len(name_bytes)))
            f.write(name_bytes)
            f.write(struct.pack('<I', len(data)))
            f.write(data)


def test_report_exists():
    assert os.path.exists(REPORT_PATH), f"Report file {REPORT_PATH} does not exist."
    assert os.path.isfile(REPORT_PATH), f"Report path {REPORT_PATH} is not a file."


def test_report_contents():
    with open(REPORT_PATH, 'r') as f:
        try:
            report = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"Report file {REPORT_PATH} is not valid JSON.")

    assert "safe_packs" in report, "Key 'safe_packs' missing from report."
    assert "malicious_packs" in report, "Key 'malicious_packs' missing from report."

    expected_safe = [
        "/home/user/incoming/valid.cfgpack"
    ]
    expected_malicious = [
        "/home/user/incoming/evil.cfgpack",
        "/home/user/incoming/subdir/absolute.cfgpack"
    ]

    assert report["safe_packs"] == expected_safe, \
        f"Expected safe_packs to be {expected_safe}, but got {report['safe_packs']}"
    assert report["malicious_packs"] == expected_malicious, \
        f"Expected malicious_packs to be {expected_malicious}, but got {report['malicious_packs']}"


def test_script_exists_and_uses_atomic_write():
    assert os.path.exists(SCRIPT_PATH), f"Script file {SCRIPT_PATH} does not exist."

    with open(SCRIPT_PATH, 'r') as f:
        source = f.read()

    try:
        tree = ast.parse(source)
    except SyntaxError:
        pytest.fail(f"Script {SCRIPT_PATH} contains a syntax error.")

    found_atomic_write = False
    for node in ast.walk(tree):
        if isinstance(node, ast.Call) and isinstance(node.func, ast.Attribute):
            func_name = node.func.attr
            if isinstance(node.func.value, ast.Name):
                module_name = node.func.value.id
                if (module_name == 'os' and func_name in ('replace', 'rename')) or \
                   (module_name == 'shutil' and func_name == 'move'):
                    found_atomic_write = True
                    break

    assert found_atomic_write, \
        "Script does not appear to use os.replace, os.rename, or shutil.move for atomic writing."


def test_script_executes_on_new_bundles_and_atomically_writes_report(tmp_path):
    token = uuid.uuid4().hex
    fixture_root = os.path.join(INCOMING, 'verify_' + token)

    safe_root = os.path.join(fixture_root, 'z_safe_' + token + '.cfgpack')
    safe_nested = os.path.join(fixture_root, 'deep', 'a_safe_' + token + '.cfgpack')
    evil_forward = os.path.join(fixture_root, 'b_evil_' + token + '.cfgpack')
    evil_backslash = os.path.join(fixture_root, 'deep', 'c_evil_' + token + '.cfgpack')
    evil_absolute = os.path.join(fixture_root, 'd_evil_' + token + '.cfgpack')
    old_evil = os.path.join(fixture_root, 'old_' + token + '.cfgpack')

    create_cfgpack(safe_root, [
        ('config/settings.ini', b'../../not-a-header'),
        ('folder/dots..okay/value.txt', b'payload')
    ])
    create_cfgpack(safe_nested, [
        ('nested/app.json', b'1234567890'),
        ('nested/second.conf', b'ok')
    ])
    create_cfgpack(evil_forward, [
        ('first/safe.txt', b'data'),
        ('area/../secret.txt', b'x')
    ])
    create_cfgpack(evil_backslash, [
        ('first/safe.txt', b'data'),
        ('area\\..\\secret.txt', b'x')
    ])
    create_cfgpack(evil_absolute, [
        ('\\server\\share\\secret.txt', b'x')
    ])
    create_cfgpack(old_evil, [('../../old-secret', b'x')])

    now = time.time()
    for path in [
        '/home/user/incoming/valid.cfgpack',
        '/home/user/incoming/evil.cfgpack',
        '/home/user/incoming/subdir/absolute.cfgpack',
        safe_root, safe_nested, evil_forward, evil_backslash, evil_absolute
    ]:
        os.utime(path, (now, now))
    old_time = now - 48 * 3600
    os.utime('/home/user/incoming/old.cfgpack', (old_time, old_time))
    os.utime(old_evil, (old_time, old_time))

    atomic_log = str(tmp_path / 'atomic.jsonl')
    runner = tmp_path / 'run_instrumented.py'
    runner.write_text(r'''import builtins
import io
import json
import os
import runpy
import shutil

REPORT = os.path.abspath('/home/user/scan_report.json')
LOG = os.environ['ATOMIC_LOG']
real_builtin_open = builtins.open
real_io_open = io.open
real_os_open = os.open
real_replace = os.replace
real_rename = os.rename
real_move = shutil.move


def normalized(path):
    try:
        return os.path.abspath(os.fspath(path))
    except TypeError:
        return None


def writing_mode(mode):
    return any(ch in mode for ch in ('w', 'a', 'x', '+'))


def guarded_open(file, mode='r', *args, **kwargs):
    if normalized(file) == REPORT and writing_mode(mode):
        raise AssertionError('report was opened directly for writing')
    return real_builtin_open(file, mode, *args, **kwargs)


def guarded_io_open(file, mode='r', *args, **kwargs):
    if normalized(file) == REPORT and writing_mode(mode):
        raise AssertionError('report was opened directly for writing')
    return real_io_open(file, mode, *args, **kwargs)


def guarded_os_open(path, flags, *args, **kwargs):
    write_flags = os.O_WRONLY | os.O_RDWR | os.O_CREAT | os.O_TRUNC | os.O_APPEND
    if normalized(path) == REPORT and flags & write_flags:
        raise AssertionError('report was opened directly for writing')
    return real_os_open(path, flags, *args, **kwargs)


def record(kind, src, dst, was_file):
    with real_builtin_open(LOG, 'a', encoding='utf-8') as f:
        f.write(json.dumps({
            'kind': kind,
            'src': normalized(src),
            'dst': normalized(dst),
            'source_was_file': was_file
        }) + '\n')


def wrapped_replace(src, dst, *args, **kwargs):
    was_file = os.path.isfile(src)
    result = real_replace(src, dst, *args, **kwargs)
    record('replace', src, dst, was_file)
    return result


def wrapped_rename(src, dst, *args, **kwargs):
    was_file = os.path.isfile(src)
    result = real_rename(src, dst, *args, **kwargs)
    record('rename', src, dst, was_file)
    return result


def wrapped_move(src, dst, *args, **kwargs):
    was_file = os.path.isfile(src)
    result = real_move(src, dst, *args, **kwargs)
    record('move', src, dst, was_file)
    return result

builtins.open = guarded_open
io.open = guarded_io_open
os.open = guarded_os_open
os.replace = wrapped_replace
os.rename = wrapped_rename
shutil.move = wrapped_move
runpy.run_path('/home/user/scan_configs.py', run_name='__main__')
''')

    if os.path.lexists(REPORT_PATH):
        if os.path.isdir(REPORT_PATH):
            shutil.rmtree(REPORT_PATH)
        else:
            os.unlink(REPORT_PATH)

    env = os.environ.copy()
    env['ATOMIC_LOG'] = atomic_log
    result = subprocess.run(
        [sys.executable, str(runner)],
        text=True,
        capture_output=True,
        timeout=20,
        env=env
    )
    assert result.returncode == 0, \
        f"Executing {SCRIPT_PATH} failed. stdout={result.stdout!r} stderr={result.stderr!r}"
    assert os.path.isfile(REPORT_PATH), "Executing the script did not create the report."

    with open(REPORT_PATH, 'r', encoding='utf-8') as f:
        report = json.load(f)

    expected_safe = sorted([
        '/home/user/incoming/valid.cfgpack',
        safe_root,
        safe_nested
    ])
    expected_malicious = sorted([
        '/home/user/incoming/evil.cfgpack',
        '/home/user/incoming/subdir/absolute.cfgpack',
        evil_forward,
        evil_backslash,
        evil_absolute
    ])
    assert report['safe_packs'] == expected_safe
    assert report['malicious_packs'] == expected_malicious
    assert old_evil not in report['safe_packs'] + report['malicious_packs']
    assert '/home/user/incoming/old.cfgpack' not in report['safe_packs'] + report['malicious_packs']
    assert report['safe_packs'] == sorted(report['safe_packs'])
    assert report['malicious_packs'] == sorted(report['malicious_packs'])
    assert all(os.path.isabs(p) for p in report['safe_packs'] + report['malicious_packs'])

    assert os.path.isfile(atomic_log), "No atomic move/replace operation was observed."
    with open(atomic_log, 'r', encoding='utf-8') as f:
        calls = [json.loads(line) for line in f if line.strip()]
    valid_calls = [
        call for call in calls
        if call['dst'] == REPORT_PATH
        and call['source_was_file']
        and call['src'] != REPORT_PATH
        and os.path.dirname(call['src']) == '/home/user'
    ]
    assert valid_calls, \
        "The generated report was not moved/replaced from a temporary file in /home/user."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
