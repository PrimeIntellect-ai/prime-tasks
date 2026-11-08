#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import importlib.util
import os
import random
import re
import stat
import subprocess
import tempfile
import uuid

import pytest

DETECTOR = '/home/user/detector.sh'


def run_detector(path):
    return subprocess.run([DETECTOR, path], capture_output=True, timeout=5)


def test_detector_script_exists_and_executable():
    detector_path = '/home/user/detector.sh'
    assert os.path.isfile(detector_path), f"Expected detector script at {detector_path} is missing."
    assert os.access(detector_path, os.X_OK), f"Detector script at {detector_path} is not executable."


def test_adversarial_corpus_classification():
    detector_path = '/home/user/detector.sh'
    evil_dir = '/app/corpus/evil/'
    clean_dir = '/app/corpus/clean/'

    assert os.path.isdir(evil_dir), f"Evil corpus directory {evil_dir} is missing."
    assert os.path.isdir(clean_dir), f"Clean corpus directory {clean_dir} is missing."

    evil_files = [f for f in os.listdir(evil_dir) if os.path.isfile(os.path.join(evil_dir, f))]
    clean_files = [f for f in os.listdir(clean_dir) if os.path.isfile(os.path.join(clean_dir, f))]

    bypassed_evil = []
    for evil_file in evil_files:
        file_path = os.path.join(evil_dir, evil_file)
        result = subprocess.run([detector_path, file_path], capture_output=True)
        if result.returncode != 1:
            bypassed_evil.append(evil_file)

    modified_clean = []
    for clean_file in clean_files:
        file_path = os.path.join(clean_dir, clean_file)
        result = subprocess.run([detector_path, file_path], capture_output=True)
        if result.returncode != 0:
            modified_clean.append(clean_file)

    errors = []
    if bypassed_evil:
        errors.append(f"{len(bypassed_evil)} of {len(evil_files)} evil bypassed: {', '.join(bypassed_evil)}")
    if modified_clean:
        errors.append(f"{len(modified_clean)} of {len(clean_files)} clean modified: {', '.join(modified_clean)}")

    if errors:
        pytest.fail(" | ".join(errors))


def test_detector_generalizes_beyond_repeated_corpus_template():
    rng = random.SystemRandom()
    nonce = uuid.uuid4().hex
    pid = rng.randint(2, 50000)
    evil = [
        f"--log-file /proc/{pid}/environ --id={rng.randint(1000, 999999)}",
        f"status --verbose --log-file=/proc/self/environ --tag={nonce}",
        f"--id={rng.randint(1000, 999999)}\n--log-file=/proc/thread-self/environ",
        f"--output=/tmp/{nonce}.txt ; --log-file=/proc/{pid}/environ",
        f"--log-file=/proc/self/cmdline --id={rng.randint(1000, 999999)}",
    ]
    clean = [
        f"--output=/tmp/{nonce}.log status --verbose",
        f"--log-file=/tmp/{nonce}.log --id={rng.randint(1000, 999999)}",
        f"status --id={rng.randint(1000, 999999)} --label=process-report",
        f"--output=/var/tmp/proc-not-real-{nonce} status",
        f"status --verbose --note={nonce}",
    ]

    with tempfile.TemporaryDirectory() as td:
        for expected, payloads in ((1, evil), (0, clean)):
            for i, payload in enumerate(payloads):
                path = os.path.join(td, f"case-{expected}-{i}")
                with open(path, 'w', encoding='utf-8') as f:
                    f.write(payload)
                result = run_detector(path)
                assert result.returncode == expected, (
                    f"Detector returned {result.returncode}, expected {expected}, for {payload!r}; "
                    f"stderr={result.stderr!r}"
                )

    assert subprocess.run([DETECTOR], capture_output=True, timeout=5).returncode != 0
    assert subprocess.run([DETECTOR, '/dev/null', '/dev/null'], capture_output=True, timeout=5).returncode != 0


def test_gateway_app_modifications():
    gateway_path = '/app/gateway/app.py'
    assert os.path.isfile(gateway_path), f"Gateway app at {gateway_path} is missing."

    with open(gateway_path, 'r') as f:
        content = f.read()

    assert 'detector.sh' in content, "Gateway app does not appear to invoke '/home/user/detector.sh'."
    assert '403' in content, "Gateway app does not appear to return an HTTP 403 status code."
    assert 'MALICIOUS' in content, "Gateway app does not appear to return the 'MALICIOUS' response body."


def test_gateway_functionally_invokes_detector_and_gates_forwarding():
    safe = 'SAFE-' + uuid.uuid4().hex
    blocked = 'BLOCK-' + uuid.uuid4().hex
    marker = tempfile.mktemp(prefix='gateway-detector-', dir='/tmp')
    backup = tempfile.mktemp(prefix='detector-backup-', dir='/tmp')
    original_mode = stat.S_IMODE(os.stat(DETECTOR).st_mode)
    os.rename(DETECTOR, backup)

    probe = f'''#!/bin/bash
[ "$#" -eq 1 ] || exit 9
case "$1" in /*) ;; *) exit 9 ;; esac
[ -f "$1" ] || exit 9
printf '%s\\n' "$(cat -- "$1")" >> {marker!r}
if [ "$(cat -- "$1")" = {blocked!r} ]; then exit 1; fi
exit 0
'''
    try:
        with open(DETECTOR, 'w', encoding='utf-8') as f:
            f.write(probe)
        os.chmod(DETECTOR, 0o755)

        spec = importlib.util.spec_from_file_location('gateway_under_test_' + uuid.uuid4().hex, '/app/gateway/app.py')
        module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)
        assert hasattr(module, 'app'), 'Gateway module does not expose its Flask app.'

        sent = []

        class FakeSocket:
            def __init__(self, *args, **kwargs):
                pass
            def connect(self, address):
                assert address == ('127.0.0.1', 9000)
            def sendall(self, data):
                sent.append(data)
            def shutdown(self, *args):
                pass
            def recv(self, size):
                return b'BACKEND_OK'
            def close(self):
                pass
            def __enter__(self):
                return self
            def __exit__(self, *args):
                self.close()

        if hasattr(module, 'socket') and hasattr(module.socket, 'socket'):
            module.socket.socket = FakeSocket

        client = module.app.test_client()
        response = client.post('/execute', data=blocked, content_type='text/plain')
        assert response.status_code == 403
        assert response.get_data(as_text=True) == 'MALICIOUS'
        assert sent == [], 'Gateway forwarded a payload after the detector rejected it.'

        response = client.post('/execute', data=safe, content_type='text/plain')
        assert response.status_code == 200
        assert sent == [safe.encode('utf-8')], 'Gateway did not forward the exact accepted payload.'

        with open(marker, encoding='utf-8') as f:
            observed = f.read().splitlines()
        assert blocked in observed and safe in observed, 'Gateway did not pass both payload files to the detector.'
    finally:
        try:
            os.unlink(DETECTOR)
        except FileNotFoundError:
            pass
        os.rename(backup, DETECTOR)
        os.chmod(DETECTOR, original_mode)
        try:
            os.unlink(marker)
        except FileNotFoundError:
            pass


def test_backend_sandboxing_modifications():
    backend_script_path = '/app/backend/start_backend.sh'
    assert os.path.isfile(backend_script_path), f"Backend start script at {backend_script_path} is missing."

    with open(backend_script_path, 'r') as f:
        content = f.read()

    has_bwrap = 'bwrap' in content
    has_unshare = 'unshare' in content

    assert has_bwrap or has_unshare, "Backend start script does not appear to use 'bwrap' or 'unshare' for sandboxing."


def test_backend_sandbox_is_on_the_executed_listener_path():
    with tempfile.TemporaryDirectory() as td:
        log = os.path.join(td, 'calls.log')

        sandbox_shim = f'''#!/bin/sh
printf '%s ' "$(basename "$0")" >> {log!r}
printf '%s ' "$@" >> {log!r}
printf '\\n' >> {log!r}
exit 0
'''
        for name in ('bwrap', 'unshare'):
            path = os.path.join(td, name)
            with open(path, 'w', encoding='utf-8') as f:
                f.write(sandbox_shim)
            os.chmod(path, 0o755)

        socat_path = os.path.join(td, 'socat')
        socat_shim = f'''#!/usr/bin/python3
import os, subprocess, sys
with open({log!r}, 'a') as f:
    f.write('socat ' + ' '.join(sys.argv[1:]) + '\\n')
for arg in sys.argv[1:]:
    if arg.startswith('EXEC:'):
        command = arg[5:].strip("\\\"'")
        command = command.replace('/usr/bin/bwrap', 'bwrap').replace('/bin/bwrap', 'bwrap')
        command = command.replace('/usr/bin/unshare', 'unshare').replace('/bin/unshare', 'unshare')
        subprocess.run(command, shell=True, env=os.environ, timeout=3)
'''
        with open(socat_path, 'w', encoding='utf-8') as f:
            f.write(socat_shim)
        os.chmod(socat_path, 0o755)

        env = os.environ.copy()
        env['PATH'] = td + os.pathsep + env.get('PATH', '')
        subprocess.run(['/bin/bash', '/app/backend/start_backend.sh'], env=env,
                       capture_output=True, timeout=5, check=False)

        assert os.path.exists(log), 'Starting the backend did not execute socat or a sandbox tool.'
        with open(log, encoding='utf-8') as f:
            calls = f.read()

        sandbox_lines = [line for line in calls.splitlines() if line.startswith(('bwrap ', 'unshare '))]
        assert sandbox_lines, f"No sandbox command was actually reached while starting the backend. Calls: {calls!r}"
        assert any('/app/backend/executor' in line or re.search(r'(^|[ /])socat([ /]|$)', line)
                   for line in sandbox_lines), (
            'The executed sandbox command does not wrap either socat or /app/backend/executor.'
        )

        valid_isolation = False
        for line in sandbox_lines:
            if line.startswith('bwrap '):
                ro_proc = re.search(r'--ro-bind(?:-try)?\s+/proc\s+/proc(?:\s|$)', line)
                private_proc = '--proc /proc' in line and '--unshare-pid' in line
                valid_isolation |= bool(ro_proc or private_proc)
            elif line.startswith('unshare '):
                has_pid = bool(re.search(r'(^|\s)(--pid|-p)(\s|$)', line))
                has_proc = '--mount-proc' in line
                valid_isolation |= has_pid and has_proc
        assert valid_isolation, (
            'The live sandbox invocation must make /proc read-only or create a private PID namespace with its own /proc.'
        )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
