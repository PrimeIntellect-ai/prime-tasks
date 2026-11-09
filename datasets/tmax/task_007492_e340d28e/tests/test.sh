#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import base64
import hashlib
import json
import os
import pathlib
import secrets
import subprocess
import sys

LOG_PATH = '/home/user/bloated_log.txt'
JSON_PATH = '/home/user/session_usage.json'


def test_json_metrics_exported_correctly():
    assert os.path.exists(JSON_PATH), f"The file {JSON_PATH} does not exist."
    assert os.path.isfile(JSON_PATH), f"The path {JSON_PATH} is not a regular file."

    try:
        with open(JSON_PATH, 'r') as f:
            data = json.load(f)
    except json.JSONDecodeError:
        assert False, f"The file {JSON_PATH} does not contain valid JSON."
    except Exception as e:
        assert False, f"Failed to read {JSON_PATH}: {e}"

    expected = {
        "sess_alpha": 3072,
        "sess_beta": 500,
        "sess_gamma": 8012
    }
    assert data == expected, f"JSON data does not match expected output. Got {data}, expected {expected}."


def test_bloated_log_symlink():
    assert os.path.lexists(LOG_PATH), f"The path {LOG_PATH} does not exist at all."
    assert os.path.islink(LOG_PATH), f"The path {LOG_PATH} is not a symbolic link."
    target = os.readlink(LOG_PATH)
    assert target == '/dev/null', f"The symlink {LOG_PATH} points to '{target}' instead of '/dev/null'."


def find_parser_scripts():
    roots = ['/home/user', '/root', '/tmp', '/opt', '/usr/local/bin']
    excluded = {
        os.path.realpath(__file__),
        '/tmp/run_parser_instrumented.py',
    }
    found = []
    for root in roots:
        if not os.path.isdir(root):
            continue
        for dirpath, dirnames, filenames in os.walk(root):
            dirnames[:] = [d for d in dirnames if d not in {'.git', '__pycache__', 'site-packages'}]
            for name in filenames:
                path = os.path.join(dirpath, name)
                if os.path.realpath(path) in excluded or os.path.islink(path) or not os.path.isfile(path):
                    continue
                try:
                    if os.path.getsize(path) > 1024 * 1024:
                        continue
                    raw = pathlib.Path(path).read_bytes()
                    text = raw.decode('utf-8')
                except Exception:
                    continue
                first = text.splitlines()[0] if text.splitlines() else ''
                if not (name.endswith('.py') or (first.startswith('#!') and 'python' in first.lower())):
                    continue
                if 'bloated_log.txt' not in text or 'session_usage.json' not in text:
                    continue
                try:
                    compile(text, path, 'exec')
                except SyntaxError:
                    continue
                found.append(path)
    return sorted(set(found), key=lambda p: os.path.getmtime(p), reverse=True)


def reset_paths(log_text, sentinel):
    if os.path.lexists(LOG_PATH):
        os.unlink(LOG_PATH)
    with open(LOG_PATH, 'w', encoding='utf-16le') as f:
        f.write(log_text)

    if os.path.lexists(JSON_PATH):
        os.unlink(JSON_PATH)
    with open(JSON_PATH, 'wb') as f:
        f.write(sentinel)


def make_case(index):
    token = secrets.token_hex(5)
    a = f'trial_{index}_{token}_a'
    b = f'trial_{index}_{token}_b'
    c = f'trial_{index}_{token}_c'
    values = [secrets.randbelow(800000) + 1 for _ in range(6)]
    text = f'''=== SESSION START: {a} ===
[INFO] Processing started
[TRACE]
  misleading number 999999
  multi-line trace output
[METRICS] BytesTransferred: {values[0]}
[METRICS] BytesTransferred: {values[1]}
=== SESSION END ===
=== SESSION START: {b} ===
[TRACE]
  BytesTransferred: 12345 without the metrics marker
[METRICS] BytesTransferred: {values[2]}
=== SESSION END ===
=== SESSION START: {c} ===
[METRICS] BytesTransferred: {values[3]}
[TRACE]
  more noise
[METRICS] BytesTransferred: {values[4]}
[METRICS] BytesTransferred: {values[5]}
=== SESSION END ===
'''
    expected = {
        a: values[0] + values[1],
        b: values[2],
        c: values[3] + values[4] + values[5],
    }
    return text, expected


def run_case(script, index):
    log_text, expected = make_case(index)
    sentinel = ('old-output-' + secrets.token_hex(16)).encode()
    reset_paths(log_text, sentinel)

    event_path = f'/tmp/atomic-events-{os.getpid()}-{index}-{secrets.token_hex(5)}.json'
    try:
        proc = subprocess.run(
            [sys.executable, '/tmp/run_parser_instrumented.py', script, event_path, JSON_PATH],
            cwd=os.path.dirname(script) or '/',
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=20,
        )
        assert proc.returncode == 0, (
            f'Parser script {script} failed with exit code {proc.returncode}. '
            f'stdout={proc.stdout!r}, stderr={proc.stderr!r}'
        )

        assert os.path.isfile(JSON_PATH) and not os.path.islink(JSON_PATH), 'JSON output is not a regular file.'
        with open(JSON_PATH, 'r') as f:
            actual = json.load(f)
        assert actual == expected, f'Parser produced {actual}, expected {expected} for a controlled UTF-16LE log.'

        assert os.path.islink(LOG_PATH), 'Parser did not replace the processed log with a symbolic link.'
        assert os.readlink(LOG_PATH) == '/dev/null', 'Processed log symlink does not point to /dev/null.'

        assert os.path.exists(event_path), 'No atomic filesystem operation record was produced.'
        with open(event_path, 'r') as f:
            events = json.load(f)

        valid_atomic_event = False
        for event in events:
            if event.get('destination') != JSON_PATH:
                continue
            if event.get('source') == JSON_PATH or event.get('source_is_symlink'):
                continue
            try:
                before = base64.b64decode(event['destination_before'])
                temporary_contents = base64.b64decode(event['source_contents'])
                temporary_json = json.loads(temporary_contents.decode('utf-8'))
            except Exception:
                continue
            if before == sentinel and temporary_json == expected:
                valid_atomic_event = True
                break
        assert valid_atomic_event, (
            'The script did not write the complete JSON to a separate temporary file and then '
            'atomically rename/replace it over the pre-existing destination.'
        )
    finally:
        if os.path.exists(event_path):
            os.unlink(event_path)


def test_python_parser_and_atomic_behavior():
    scripts = find_parser_scripts()
    assert scripts, 'No Python parser script for bloated_log.txt and session_usage.json was found.'

    failures = []
    for script in scripts:
        try:
            run_case(script, 1)
            run_case(script, 2)
            return
        except Exception as e:
            failures.append(f'{script}: {e}')
    assert False, 'No submitted Python script met the parsing and atomic-write requirements:\n' + '\n'.join(failures)
TEST_EOF

cat << 'WRAPPER_EOF' > /tmp/run_parser_instrumented.py
import base64
import json
import os
import runpy
import sys

script, event_path, destination = sys.argv[1:4]
events = []
original_replace = os.replace
original_rename = os.rename


def absolute_path(value):
    return os.path.abspath(os.fspath(value))


def capture_and_call(original, source, target, *args, **kwargs):
    source_abs = absolute_path(source)
    target_abs = absolute_path(target)
    if target_abs == destination:
        event = {
            'source': source_abs,
            'destination': target_abs,
            'source_is_symlink': os.path.islink(source_abs),
        }
        try:
            with open(source_abs, 'rb') as f:
                event['source_contents'] = base64.b64encode(f.read()).decode('ascii')
        except Exception:
            event['source_contents'] = ''
        try:
            with open(target_abs, 'rb') as f:
                event['destination_before'] = base64.b64encode(f.read()).decode('ascii')
        except Exception:
            event['destination_before'] = ''
        events.append(event)
    return original(source, target, *args, **kwargs)


def checked_replace(source, target, *args, **kwargs):
    return capture_and_call(original_replace, source, target, *args, **kwargs)


def checked_rename(source, target, *args, **kwargs):
    return capture_and_call(original_rename, source, target, *args, **kwargs)


os.replace = checked_replace
os.rename = checked_rename
exit_error = None
try:
    sys.argv = [script]
    runpy.run_path(script, run_name='__main__')
except SystemExit as exc:
    if exc.code not in (None, 0):
        exit_error = exc
except BaseException as exc:
    exit_error = exc
finally:
    with open(event_path, 'w') as f:
        json.dump(events, f)

if exit_error is not None:
    raise exit_error
WRAPPER_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
