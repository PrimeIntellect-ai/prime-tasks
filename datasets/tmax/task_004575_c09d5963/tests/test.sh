#!/bin/bash
set -e
mkdir -p /logs/verifier

cat <<'PY_EOF' > /tmp/verify_extract_errors.py
import os
import re
import secrets
import subprocess
import sys
import time
from pathlib import Path

SCRIPT = Path('/home/user/extract_errors.py')
LOG = Path('/home/user/service.log')
STATE = Path('/home/user/backup.state')
ARCHIVE = Path('/home/user/error_archive.log')
RUNNER = Path('/tmp/instrumented_runner.py')

EXPECTED_FIRST_ERROR = (
    b'[2023-10-25 10:05:00] ERROR Connection timeout\n'
    b'Traceback (most recent call last):\n'
    b'  File "main.py", line 10, in <module>\n'
    b'TimeoutError: db unreachable\n'
)

RUNNER.write_text(r'''import os
import runpy
import sys
import time
import types
import fcntl as real_fcntl
import mmap as real_mmap

trace_path = os.environ.get('TRACE_PATH')
barrier = os.environ.get('START_BARRIER')
if barrier:
    deadline = time.time() + 15
    while not os.path.exists(barrier):
        if time.time() > deadline:
            raise RuntimeError('timed out waiting for concurrency barrier')
        time.sleep(0.002)

def record(kind, fd, extra=''):
    if not trace_path:
        return
    try:
        target = os.readlink('/proc/self/fd/%d' % int(fd))
    except Exception:
        target = '<unknown>'
    line = '%s|%s|%s\n' % (kind, target, extra)
    out = os.open(trace_path, os.O_WRONLY | os.O_CREAT | os.O_APPEND, 0o666)
    try:
        os.write(out, line.encode())
    finally:
        os.close(out)

fcntl_proxy = types.ModuleType('fcntl')
fcntl_proxy.__dict__.update(real_fcntl.__dict__)
def traced_flock(fd, operation):
    record('flock', fd, str(operation))
    return real_fcntl.flock(fd, operation)
fcntl_proxy.flock = traced_flock

mmap_proxy = types.ModuleType('mmap')
mmap_proxy.__dict__.update(real_mmap.__dict__)
def traced_mmap(fd, *args, **kwargs):
    record('mmap', fd)
    return real_mmap.mmap(fd, *args, **kwargs)
mmap_proxy.mmap = traced_mmap

sys.modules['fcntl'] = fcntl_proxy
sys.modules['mmap'] = mmap_proxy
runpy.run_path(sys.argv[1], run_name='__main__')
''')


def state_value():
    assert STATE.is_file(), 'backup.state does not exist'
    raw = STATE.read_text()
    assert re.fullmatch(r'\s*\d+\s*', raw), 'backup.state must contain a single integer'
    return int(raw.strip())


def archive_bytes():
    assert ARCHIVE.is_file(), 'error_archive.log does not exist'
    return ARCHIVE.read_bytes()


def run_script(trace, barrier=None):
    env = os.environ.copy()
    env['TRACE_PATH'] = str(trace)
    if barrier is not None:
        env['START_BARRIER'] = str(barrier)
    return subprocess.Popen(
        [sys.executable, str(RUNNER), str(SCRIPT)],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        env=env,
    )


def wait_ok(proc, label):
    out, err = proc.communicate(timeout=30)
    assert proc.returncode == 0, '%s failed:\nstdout=%r\nstderr=%r' % (label, out, err)


def assert_instrumented(trace, require_mmap=True):
    data = trace.read_text() if trace.exists() else ''
    flock_lines = [line for line in data.splitlines() if line.startswith('flock|')]
    assert flock_lines, 'script did not actually call fcntl.flock'
    assert any('/home/user/backup.state|' in line for line in flock_lines), \
        'fcntl.flock was not applied to backup.state'
    lock_ex = 2
    assert any(int(line.rsplit('|', 1)[1]) & lock_ex for line in flock_lines), \
        'backup.state was not locked with LOCK_EX'
    if require_mmap:
        mmap_lines = [line for line in data.splitlines() if line.startswith('mmap|')]
        assert any('/home/user/service.log|' in line for line in mmap_lines), \
            'script did not actually mmap service.log'


# Preserve the original existence, source, and initial-run assertions.
assert SCRIPT.is_file(), 'extract_errors.py does not exist'
source = SCRIPT.read_text()
assert 'fcntl' in source, 'Script does not import or use fcntl.'
assert 'flock' in source, 'Script does not use fcntl.flock.'
assert 'mmap' in source, 'Script does not import or use mmap.'
assert STATE.is_file(), 'Initial backup.state does not exist'
assert ARCHIVE.is_file(), 'Initial error_archive.log does not exist'
assert state_value() == LOG.stat().st_size, 'Initial state does not equal service.log size'
assert archive_bytes() == EXPECTED_FIRST_ERROR, 'Initial archive content is incorrect'

# Build a fresh, unpredictable log to test general parsing and exact preservation.
token = secrets.token_hex(12).encode()
initial_log = (
    b'[2041-02-03 04:05:06] INFO boot-' + token + b'\n'
    b'info continuation ' + token + b'\n'
    b'[2041-02-03 04:05:07] ERROR first-' + token + b'\n'
    b'Trace line one ' + token + b'\n'
    b'  indented trace line\n'
    b'[2041-02-03 04:05:08] INFO between-' + token + b'\n'
    b'[2041-02-03 04:05:09] ERROR second-' + token + b'\n'
    b'last detail ' + token + b'\n'
)
expected = (
    b'[2041-02-03 04:05:07] ERROR first-' + token + b'\n'
    b'Trace line one ' + token + b'\n'
    b'  indented trace line\n'
    b'[2041-02-03 04:05:09] ERROR second-' + token + b'\n'
    b'last detail ' + token + b'\n'
)
LOG.write_bytes(initial_log)
for path in (STATE, ARCHIVE):
    try:
        path.unlink()
    except FileNotFoundError:
        pass
trace1 = Path('/tmp/extract_trace_1')
trace1.unlink(missing_ok=True)
p = run_script(trace1)
wait_ok(p, 'fresh randomized run')
assert_instrumented(trace1)
assert state_value() == len(initial_log), 'Fresh run wrote the wrong byte offset'
assert archive_bytes() == expected, 'General multi-line ERROR extraction failed'

# Verify that an unterminated event is retained for the next incremental run.
complete_info = b'[2041-02-03 04:06:00] INFO incremental-' + token + b'\n'
partial_error = b'[2041-02-03 04:06:01] ERROR split-' + token
old_size = len(initial_log)
with LOG.open('ab') as f:
    f.write(complete_info + partial_error)
trace2 = Path('/tmp/extract_trace_2')
trace2.unlink(missing_ok=True)
p = run_script(trace2)
wait_ok(p, 'partial-record run')
assert_instrumented(trace2)
assert archive_bytes() == expected, 'An incomplete ERROR event was archived'
assert state_value() == old_size + len(complete_info), \
    'State advanced beyond an incomplete event'

completion = (
    b' completed\n'
    b'split stack ' + token + b'\n'
    b'[2041-02-03 04:06:02] INFO closes-split-' + token + b'\n'
)
with LOG.open('ab') as f:
    f.write(completion)
split_expected = partial_error + completion.split(b'[2041-02-03 04:06:02]', 1)[0]
expected += split_expected
trace3 = Path('/tmp/extract_trace_3')
trace3.unlink(missing_ok=True)
p = run_script(trace3)
wait_ok(p, 'completed split-record run')
assert_instrumented(trace3)
assert state_value() == LOG.stat().st_size, 'Completed incremental run wrote wrong state'
assert archive_bytes() == expected, 'Split ERROR event was not reconstructed exactly'

# Launch multiple jobs together after a sizable append. Correct locking must prevent
# duplicate extraction and lost/corrupt state updates.
large_body = b'X' * (1024 * 1024) + token
concurrent_data = (
    b'[2041-02-03 04:07:00] INFO concurrency-start-' + token + b'\n'
    b'[2041-02-03 04:07:01] ERROR concurrent-' + token + b'\n'
    b'large trace ' + large_body + b'\n'
    b'[2041-02-03 04:07:02] INFO concurrency-end-' + token + b'\n'
    b'[2041-02-03 04:07:03] ERROR final-' + token + b'\n'
    b'final detail\n'
)
concurrent_errors = (
    b'[2041-02-03 04:07:01] ERROR concurrent-' + token + b'\n'
    b'large trace ' + large_body + b'\n'
    b'[2041-02-03 04:07:03] ERROR final-' + token + b'\n'
    b'final detail\n'
)
with LOG.open('ab') as f:
    f.write(concurrent_data)
expected += concurrent_errors

barrier = Path('/tmp/extract_start_barrier')
barrier.unlink(missing_ok=True)
procs = []
traces = []
for i in range(5):
    trace = Path('/tmp/extract_concurrent_%d' % i)
    trace.unlink(missing_ok=True)
    traces.append(trace)
    procs.append(run_script(trace, barrier))
time.sleep(0.15)
barrier.write_text('go')
for i, proc in enumerate(procs):
    wait_ok(proc, 'concurrent process %d' % i)
for trace in traces:
    assert_instrumented(trace, require_mmap=False)
assert any('mmap|/home/user/service.log|' in t.read_text() for t in traces if t.exists()), \
    'No concurrent worker mmaped service.log'
assert state_value() == LOG.stat().st_size, 'Concurrent runs left an incorrect state offset'
assert archive_bytes() == expected, 'Concurrent runs duplicated, omitted, or corrupted ERROR records'
PY_EOF

if python3 /tmp/verify_extract_errors.py 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
