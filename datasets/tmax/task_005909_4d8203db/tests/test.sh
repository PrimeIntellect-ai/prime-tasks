#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import secrets
import shutil
import signal
import subprocess
import time

REQUESTS = '/home/user/requests'
OUTBOX = '/home/user/mail/outbox'
SUPERVISOR_PID = '/home/user/supervisor.pid'
WORKER = '/home/user/worker'
SUPERVISOR = '/home/user/supervisor.sh'


def wait_until(predicate, timeout=8.0, interval=0.1):
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        try:
            if predicate():
                return True
        except (FileNotFoundError, ProcessLookupError):
            pass
        time.sleep(interval)
    return False


def clean_dir(path):
    for name in os.listdir(path):
        target = os.path.join(path, name)
        if os.path.isdir(target) and not os.path.islink(target):
            shutil.rmtree(target)
        else:
            os.remove(target)


def read_pid():
    with open(SUPERVISOR_PID, 'r') as f:
        value = f.read().strip()
    assert value.isdigit(), 'PID file does not contain a valid integer.'
    return int(value)


def process_exists(pid):
    try:
        os.kill(pid, 0)
        return True
    except OSError:
        return False


def proc_ppid(pid):
    with open(f'/proc/{pid}/stat', 'r') as f:
        stat = f.read()
    # The comm field can contain spaces and parentheses, so parse after its last ')'.
    return int(stat[stat.rfind(')') + 2:].split()[1])


def descendants(root):
    found = set()
    frontier = {root}
    while frontier:
        parents = frontier
        frontier = set()
        for entry in os.listdir('/proc'):
            if not entry.isdigit():
                continue
            pid = int(entry)
            if pid in found or pid == root:
                continue
            try:
                if proc_ppid(pid) in parents:
                    found.add(pid)
                    frontier.add(pid)
            except (FileNotFoundError, ProcessLookupError, PermissionError, ValueError):
                pass
    return found


def worker_descendants(supervisor_pid):
    expected = os.path.realpath(WORKER)
    result = []
    for pid in descendants(supervisor_pid):
        try:
            if os.path.realpath(f'/proc/{pid}/exe') == expected:
                result.append(pid)
        except (FileNotFoundError, ProcessLookupError, PermissionError):
            pass
    return result


def worker_environment(pid):
    with open(f'/proc/{pid}/environ', 'rb') as f:
        entries = f.read().split(b'\0')
    env = {}
    for entry in entries:
        if b'=' in entry:
            key, value = entry.split(b'=', 1)
            env[key.decode(errors='replace')] = value.decode(errors='replace')
    return env


def expected_email(username, email):
    return (
        'From: admin@system.local\n'
        f'To: {email}\n'
        f'Subject: Welcome to the system, {username}\n\n'
        'Your account has been provisioned.\n'
    )


def submit_and_check(filename, username, email, timeout=7.0):
    request = os.path.join(REQUESTS, filename)
    output = os.path.join(OUTBOX, username + '.eml')
    with open(request, 'w') as f:
        json.dump({'username': username, 'email': email}, f)

    assert wait_until(lambda: os.path.exists(output) and not os.path.exists(request), timeout), (
        f'{filename} was not generally processed into {username}.eml.'
    )
    with open(output, 'r') as f:
        content = f.read()
    assert content == expected_email(username, email), (
        f'{username}.eml content is incorrect. Got:\n{content}'
    )


def test_directories_exist():
    assert os.path.isdir(REQUESTS), '/home/user/requests directory does not exist.'
    assert os.path.isdir(OUTBOX), '/home/user/mail/outbox directory does not exist.'


def test_files_exist_and_executable_and_are_go_artifacts():
    assert os.path.isfile('/home/user/worker.go'), '/home/user/worker.go does not exist.'
    assert os.path.isfile(WORKER), '/home/user/worker does not exist.'
    assert os.access(WORKER, os.X_OK), '/home/user/worker is not executable.'

    with open(WORKER, 'rb') as f:
        assert f.read(4) == b'\x7fELF', '/home/user/worker is not a compiled Linux executable.'

    metadata = subprocess.run(
        ['go', 'version', '-m', WORKER], capture_output=True, text=True, timeout=10
    )
    assert metadata.returncode == 0 and 'go1' in (metadata.stdout + metadata.stderr), (
        '/home/user/worker is not recognizable as a Go-compiled executable.'
    )

    # Independently ensure the required source is a complete, compilable Go program.
    source_build = '/tmp/worker-source-build'
    built = subprocess.run(
        ['go', 'build', '-o', source_build, '/home/user/worker.go'],
        capture_output=True, text=True, timeout=30
    )
    assert built.returncode == 0, f'/home/user/worker.go does not compile: {built.stderr}'

    assert os.path.isfile(SUPERVISOR), '/home/user/supervisor.sh does not exist.'
    assert os.access(SUPERVISOR, os.X_OK), '/home/user/supervisor.sh is not executable.'
    assert os.path.isfile(SUPERVISOR_PID), '/home/user/supervisor.pid does not exist.'


def test_supervisor_running_and_owns_worker():
    pid = read_pid()
    assert process_exists(pid), f'Supervisor process with PID {pid} is not running.'

    with open(f'/proc/{pid}/cmdline', 'rb') as f:
        cmdline = f.read().replace(b'\0', b' ')
    assert b'/home/user/supervisor.sh' in cmdline, (
        'The PID file does not identify the running supervisor script itself.'
    )

    assert wait_until(lambda: len(worker_descendants(pid)) == 1, 5), (
        'The supervisor does not own exactly one running /home/user/worker process.'
    )
    worker_pid = worker_descendants(pid)[0]
    env = worker_environment(worker_pid)
    assert env.get('PROVISION_DIR') == REQUESTS
    assert env.get('OUTBOX_DIR') == OUTBOX
    assert env.get('FROM_EMAIL') == 'admin@system.local'


def test_worker_functionality_and_supervisor_restart():
    clean_dir(REQUESTS)
    clean_dir(OUTBOX)
    supervisor_pid = read_pid()

    # Preserve the original normal-processing assertions.
    submit_and_check('alice.json', 'alice', 'alice@test.domain')

    workers = worker_descendants(supervisor_pid)
    assert len(workers) == 1
    stable_worker = workers[0]

    # Invalid JSON must not crash the worker and must not prevent later valid work.
    malformed = os.path.join(REQUESTS, 'zzzz-invalid-' + secrets.token_hex(6) + '.json')
    with open(malformed, 'w') as f:
        f.write('{ this is not valid JSON')
    time.sleep(2.2)
    assert process_exists(stable_worker), 'The Go worker crashed on invalid JSON.'
    submit_and_check('aaaa-after-invalid-' + secrets.token_hex(6) + '.json',
                     'valid_' + secrets.token_hex(5),
                     secrets.token_hex(6) + '@invalid-test.example')
    assert process_exists(stable_worker), 'The worker restarted while handling invalid JSON.'
    if os.path.exists(malformed):
        os.remove(malformed)

    # Exercise general JSON processing with unpredictable names and values.
    cases = []
    for _ in range(4):
        token = secrets.token_hex(7)
        cases.append((f'request-{secrets.token_hex(6)}.json',
                      f'user_{token}', f'{token}+welcome@example.test'))
    for filename, username, email in cases:
        submit_and_check(filename, username, email)

    # Preserve the original crash assertion, while also proving the worker PID exits.
    workers = worker_descendants(supervisor_pid)
    assert len(workers) == 1
    old_worker = workers[0]
    bob_json = os.path.join(REQUESTS, 'bob.json')
    with open(bob_json, 'w') as f:
        json.dump({'username': 'bob', 'crash': True}, f)

    assert wait_until(lambda: not process_exists(old_worker), 7), (
        'A request with crash=true did not make the worker exit.'
    )
    assert os.path.exists(bob_json), (
        'bob.json was deleted, but it should have caused a crash and been left alone.'
    )

    # Remove the persistent crash request after observing it so a restarted worker can recover.
    os.remove(bob_json)
    assert wait_until(
        lambda: len(worker_descendants(supervisor_pid)) == 1
                and worker_descendants(supervisor_pid)[0] != old_worker,
        7
    ), 'The supervisor did not restart /home/user/worker after its crash.'

    # Preserve the original recovery assertions.
    charlie_json = os.path.join(REQUESTS, 'charlie.json')
    charlie_eml = os.path.join(OUTBOX, 'charlie.eml')
    with open(charlie_json, 'w') as f:
        json.dump({'username': 'charlie', 'email': 'charlie@test.domain'}, f)
    assert wait_until(lambda: os.path.exists(charlie_eml) and not os.path.exists(charlie_json), 7), (
        'charlie.eml was not created. The supervisor may not have restarted the worker.'
    )
    with open(charlie_eml, 'r') as f:
        assert f.read() == expected_email('charlie', 'charlie@test.domain')


def test_cleanup():
    if os.path.exists(SUPERVISOR_PID):
        try:
            pid = read_pid()
            for child in descendants(pid):
                try:
                    os.kill(child, signal.SIGTERM)
                except OSError:
                    pass
            os.kill(pid, signal.SIGTERM)
        except (OSError, AssertionError):
            pass
TEST_EOF

status=0
python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1 || status=$?

# Best-effort cleanup even when pytest stopped before its cleanup test.
if [ -f /home/user/supervisor.pid ]; then
    pid="$(cat /home/user/supervisor.pid 2>/dev/null || true)"
    if [[ "$pid" =~ ^[0-9]+$ ]]; then
        kill "$pid" 2>/dev/null || true
    fi
fi
pkill -f '^/home/user/worker$' 2>/dev/null || true

if [ "$status" -eq 0 ]; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
