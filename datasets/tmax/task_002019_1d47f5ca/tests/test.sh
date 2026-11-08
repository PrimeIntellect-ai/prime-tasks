#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import random
import signal
import subprocess
import tempfile
import time
import urllib.error
import urllib.request
import uuid

import pytest


def worker_pids():
    pids = []
    for name in os.listdir('/proc'):
        if not name.isdigit() or int(name) == os.getpid():
            continue
        try:
            with open(f'/proc/{name}/cmdline', 'rb') as fh:
                argv = [x.decode(errors='replace') for x in fh.read().split(b'\0') if x]
            if any(os.path.basename(arg) == 'worker.sh' for arg in argv):
                pids.append(int(name))
        except (FileNotFoundError, ProcessLookupError, PermissionError):
            pass
    return pids


def signal_workers(sig):
    for pid in worker_pids():
        try:
            os.kill(pid, sig)
        except ProcessLookupError:
            pass


def test_filter_script_corpus():
    clean_dir = "/app/corpus/clean"
    evil_dir = "/app/corpus/evil"

    assert os.path.exists("/app/filter.sh"), "/app/filter.sh does not exist"
    assert os.access("/app/filter.sh", os.X_OK), "/app/filter.sh is not executable"

    clean_files = sorted([os.path.join(clean_dir, f) for f in os.listdir(clean_dir) if os.path.isfile(os.path.join(clean_dir, f))])
    evil_files = sorted([os.path.join(evil_dir, f) for f in os.listdir(evil_dir) if os.path.isfile(os.path.join(evil_dir, f))])

    assert len(clean_files) > 0, "No clean files found"
    assert len(evil_files) > 0, "No evil files found"

    clean_modified = []
    evil_bypassed = []

    for f in clean_files:
        res = subprocess.run(["/app/filter.sh", f], capture_output=True, text=True)
        if res.stdout.strip() != "ACCEPT":
            clean_modified.append(os.path.basename(f))

    for f in evil_files:
        res = subprocess.run(["/app/filter.sh", f], capture_output=True, text=True)
        if res.stdout.strip() != "REJECT":
            evil_bypassed.append(os.path.basename(f))

    err_msgs = []
    if evil_bypassed:
        err_msgs.append(f"{len(evil_bypassed)} of {len(evil_files)} evil bypassed: {', '.join(evil_bypassed)}")
    if clean_modified:
        err_msgs.append(f"{len(clean_modified)} of {len(clean_files)} clean modified: {', '.join(clean_modified)}")

    assert not err_msgs, " | ".join(err_msgs)


def test_filter_on_unlabeled_inputs_and_parallel_iterations():
    parallel = '/usr/bin/parallel'
    real_parallel = '/usr/bin/parallel.verifier-real'
    assert os.path.isfile(parallel), 'GNU parallel is not installed at /usr/bin/parallel'
    assert not os.path.exists(real_parallel), 'Unexpected verifier backup path already exists'

    stopped = worker_pids()
    for pid in stopped:
        try:
            os.kill(pid, signal.SIGSTOP)
        except ProcessLookupError:
            pass

    os.rename(parallel, real_parallel)
    try:
        with tempfile.TemporaryDirectory(prefix='sensor-validation-') as td:
            wrapper = '''#!/bin/bash
set -e
logdir="$VERIFY_PARALLEL_DIR"
mkdir -p "$logdir"
lock="$logdir/counter.lock"
while ! mkdir "$lock" 2>/dev/null; do sleep 0.01; done
n=0
[ ! -f "$logdir/counter" ] || n=$(cat "$logdir/counter")
n=$((n+1))
printf '%s\n' "$n" > "$logdir/counter"
rmdir "$lock"
exec /usr/bin/parallel.verifier-real --joblog "$logdir/joblog.$n" "$@"
'''
            with open(parallel, 'w') as fh:
                fh.write(wrapper)
            os.chmod(parallel, 0o755)

            clean_path = os.path.join(td, uuid.uuid4().hex + '.dat')
            evil_path = os.path.join(td, uuid.uuid4().hex + '.dat')

            clean_values = [40.0, 60.0] * 500
            evil_values = [57.0, 59.0] * 500
            random.SystemRandom().shuffle(clean_values)
            random.SystemRandom().shuffle(evil_values)
            with open(clean_path, 'w') as fh:
                fh.writelines(f'{v:.6f}\n' for v in clean_values)
            with open(evil_path, 'w') as fh:
                fh.writelines(f'{v:.6f}\n' for v in evil_values)

            for path, expected in [(clean_path, 'ACCEPT'), (evil_path, 'REJECT')]:
                logdir = os.path.join(td, 'logs-' + uuid.uuid4().hex)
                os.mkdir(logdir)
                env = os.environ.copy()
                env['VERIFY_PARALLEL_DIR'] = logdir
                result = subprocess.run(['/app/filter.sh', path], capture_output=True,
                                        text=True, timeout=120, env=env)
                assert result.returncode == 0, result.stderr
                assert result.stdout.strip() == expected, (
                    f'Expected {expected} for generated unlabeled input, got {result.stdout!r}'
                )

                logs = sorted(name for name in os.listdir(logdir) if name.startswith('joblog.'))
                assert len(logs) == 1, (
                    f'Filter must use one GNU parallel invocation for its bootstrap; found {len(logs)}'
                )
                with open(os.path.join(logdir, logs[0])) as fh:
                    rows = [line for line in fh.read().splitlines()[1:] if line.strip()]
                assert len(rows) == 500, (
                    f'GNU parallel executed {len(rows)} bootstrap jobs instead of exactly 500'
                )
    finally:
        try:
            if os.path.exists(parallel):
                os.unlink(parallel)
            if os.path.exists(real_parallel):
                os.rename(real_parallel, parallel)
        finally:
            for pid in stopped:
                try:
                    os.kill(pid, signal.SIGCONT)
                except ProcessLookupError:
                    pass


def test_pipeline_services_running():
    # Check if Redis is running on the correct port
    res = subprocess.run(["redis-cli", "-h", "127.0.0.1", "-p", "6379", "PING"], capture_output=True, text=True)
    assert "PONG" in res.stdout, "Redis server is not responding on 127.0.0.1:6379"

    # Check if Flask API is responding
    try:
        # Just checking if the port is open and responding to HTTP
        req = urllib.request.Request("http://127.0.0.1:8080/ingest", data=b"/dev/null", method="POST")
        response = urllib.request.urlopen(req, timeout=5)
        assert response.status in [200, 201, 202], f"API responded with unexpected status {response.status}"
    except urllib.error.HTTPError as e:
        # If the API returns a 400 or 500, it's at least running, but 200 is expected for a valid path
        pass
    except Exception as e:
        pytest.fail(f"Flask API is not reachable on 127.0.0.1:8080: {e}")

    # Verify the worker script is running
    res = subprocess.run(["pgrep", "-f", "worker.sh"], capture_output=True, text=True)
    assert res.stdout.strip() != "", "worker.sh daemon is not running in the background"


def test_post_reaches_task_queue_and_worker_invokes_filter():
    pids = worker_pids()
    assert pids, 'No running worker.sh process found'
    for pid in pids:
        os.kill(pid, signal.SIGSTOP)

    filter_path = '/app/filter.sh'
    saved_filter = '/app/filter.sh.verifier-original'
    marker = f'/tmp/filter-invocation-{uuid.uuid4().hex}'
    submitted = f'/tmp/submitted-{uuid.uuid4().hex}.txt'
    with open(submitted, 'w') as fh:
        fh.writelines('50.000000\n' for _ in range(1000))

    assert not os.path.exists(saved_filter), 'Unexpected verifier filter backup already exists'
    os.rename(filter_path, saved_filter)
    try:
        probe = f'''#!/bin/bash
printf '%s\\t' "$1" >> {marker!r}
tr '\\0' ' ' < "/proc/$PPID/cmdline" >> {marker!r} 2>/dev/null || true
printf '\\n' >> {marker!r}
exec {saved_filter!r} "$@"
'''
        with open(filter_path, 'w') as fh:
            fh.write(probe)
        os.chmod(filter_path, 0o755)

        subprocess.run(['redis-cli', '-h', '127.0.0.1', '-p', '6379', 'DEL', 'task_queue'],
                       check=True, capture_output=True, text=True)
        req = urllib.request.Request('http://127.0.0.1:8080/ingest',
                                     data=submitted.encode(), method='POST')
        with urllib.request.urlopen(req, timeout=5) as response:
            assert response.status in [200, 201, 202]

        queued = subprocess.run(
            ['redis-cli', '-h', '127.0.0.1', '-p', '6379', 'LRANGE', 'task_queue', '0', '-1'],
            check=True, capture_output=True, text=True
        ).stdout.splitlines()
        assert submitted in queued, 'POSTed path was not pushed to Redis queue task_queue'

        for pid in pids:
            try:
                os.kill(pid, signal.SIGCONT)
            except ProcessLookupError:
                pass

        deadline = time.time() + 15
        while time.time() < deadline and not os.path.exists(marker):
            time.sleep(0.1)
        assert os.path.exists(marker), 'Worker did not invoke /app/filter.sh for the queued path'
        with open(marker) as fh:
            entries = fh.read().splitlines()
        matching = [line for line in entries if line.split('\t', 1)[0] == submitted]
        assert matching, 'Worker invoked the filter with a path other than the POSTed path'
        assert any('worker.sh' in line for line in matching), (
            'The queued path did not reach /app/filter.sh from worker.sh'
        )
    finally:
        for pid in pids:
            try:
                os.kill(pid, signal.SIGCONT)
            except ProcessLookupError:
                pass
        if os.path.exists(filter_path):
            os.unlink(filter_path)
        if os.path.exists(saved_filter):
            os.rename(saved_filter, filter_path)
        for path in (marker, submitted):
            try:
                os.unlink(path)
            except FileNotFoundError:
                pass
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
