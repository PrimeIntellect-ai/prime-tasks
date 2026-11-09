#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import os
import pwd
import py_compile
import random
import stat
import subprocess
from datetime import datetime, timedelta

try:
    from zoneinfo import ZoneInfo
except ImportError:
    import pytz

SUPERVISOR = '/home/user/alert_supervisor.py'
ALERTS = '/home/user/alerts.csv'
EVENTS = '/tmp/.supervisor_events'
READY = '/tmp/.env_ready'
CRASHED = '/tmp/.crashed_once'


def test_supervisor_and_alerts_f1_score():
    assert os.path.exists(SUPERVISOR), f'Required supervisor {SUPERVISOR} does not exist.'
    assert not os.path.islink(SUPERVISOR), 'alert_supervisor.py must be a real Python file, not a symlink.'
    assert stat.S_ISREG(os.stat(SUPERVISOR).st_mode), 'alert_supervisor.py is not a regular file.'
    py_compile.compile(SUPERVISOR, doraise=True)

    for path in (ALERTS, EVENTS, READY, CRASHED):
        try:
            os.remove(path)
        except FileNotFoundError:
            pass

    # Install instrumented versions of the required dependencies. Their externally
    # visible behavior and deterministic records match the originals, while the
    # event log proves initialization, launch ordering, and restart behavior.
    with open('/home/user/init_env.sh', 'w') as f:
        f.write('''#!/bin/bash
sleep 1
echo "INITIALIZED=1" > /tmp/.env_ready
echo "INIT" >> /tmp/.supervisor_events
exit 0
''')

    with open('/home/user/generate_logs.py', 'w') as f:
        f.write(r'''#!/usr/bin/env python3
import os
import random
import sys
from datetime import datetime, timedelta

with open('/tmp/.supervisor_events', 'a') as events:
    events.write('GEN\n')

if not os.path.exists('/tmp/.env_ready'):
    sys.stderr.write('Fatal: Environment not initialized.\n')
    sys.exit(1)

random.seed(42)
start_time = datetime(2023, 10, 1, 0, 0, 0)
processes = ['worker_daemon', 'web_server', 'db_writer']

for i in range(5000):
    current_time = start_time + timedelta(minutes=i)
    proc = random.choice(processes)
    load = round(random.uniform(10.0, 99.9), 1)

    if i == 2500 and not os.path.exists('/tmp/.crashed_once'):
        with open('/tmp/.crashed_once', 'w') as marker:
            marker.write('1')
        sys.exit(2)

    print(f"{current_time.strftime('%Y-%m-%d %H:%M:%S')}|{proc}|{load}")

sys.exit(0)
''')

    os.chmod('/home/user/init_env.sh', 0o755)
    os.chmod('/home/user/generate_logs.py', 0o755)
    os.chown('/home/user/init_env.sh', 0, 0)
    os.chown('/home/user/generate_logs.py', 0, 0)

    user = pwd.getpwnam('user')
    with open(ALERTS, 'w'):
        pass
    os.chown(ALERTS, user.pw_uid, user.pw_gid)
    os.chmod(ALERTS, 0o644)

    # Prevent the submitted process from replacing the instrumented dependencies.
    os.chmod('/home/user', 0o755)

    def demote():
        os.setgid(user.pw_gid)
        os.setuid(user.pw_uid)

    env = os.environ.copy()
    env['HOME'] = '/home/user'
    result = subprocess.run(
        ['python3', SUPERVISOR],
        cwd='/home/user',
        env=env,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=45,
        preexec_fn=demote,
    )
    assert result.returncode == 0, (
        f'Supervisor exited with status {result.returncode}. '
        f'stdout={result.stdout[-1000:]!r}, stderr={result.stderr[-1000:]!r}'
    )

    assert os.path.exists(EVENTS), 'The supervisor never executed init_env.sh or generate_logs.py.'
    with open(EVENTS) as f:
        events = [line.strip() for line in f if line.strip()]

    assert events and events[0] == 'INIT', (
        'init_env.sh must complete before generate_logs.py is launched.'
    )
    assert events.count('INIT') >= 1, 'The supervisor did not execute init_env.sh.'
    assert events.count('GEN') == 2, (
        'generate_logs.py must be launched once, restarted after its non-zero exit, '
        'and not restarted after its successful exit.'
    )

    random.seed(42)
    start_time = datetime(2023, 10, 1, 0, 0, 0)
    processes = ['worker_daemon', 'web_server', 'db_writer']
    expected_alerts = set()

    try:
        tz = ZoneInfo('Asia/Tokyo')
        utc_tz = ZoneInfo('UTC')
    except NameError:
        tz = pytz.timezone('Asia/Tokyo')
        utc_tz = pytz.utc

    for i in range(5000):
        current_time = start_time + timedelta(minutes=i)
        proc = random.choice(processes)
        load = round(random.uniform(10.0, 99.9), 1)

        if proc == 'worker_daemon' and load > 82.5:
            utc_dt = current_time.replace(tzinfo=utc_tz)
            tokyo_dt = utc_dt.astimezone(tz)
            expected_alerts.add(
                f"{tokyo_dt.strftime('%Y-%m-%d %H:%M:%S')},{proc},{load}"
            )

    assert os.path.exists(ALERTS), (
        f'Output file {ALERTS} does not exist. The supervisor failed to produce the alerts file.'
    )

    agent_alerts = set()
    with open(ALERTS, 'r') as f:
        reader = csv.reader(f)
        for row in reader:
            if row and len(row) >= 3:
                agent_alerts.add(f'{row[0].strip()},{row[1].strip()},{row[2].strip()}')

    true_positives = len(expected_alerts.intersection(agent_alerts))
    false_positives = len(agent_alerts - expected_alerts)
    false_negatives = len(expected_alerts - agent_alerts)

    if true_positives == 0:
        f1 = 0.0
    else:
        precision = true_positives / (true_positives + false_positives)
        recall = true_positives / (true_positives + false_negatives)
        f1 = 2 * precision * recall / (precision + recall)

    assert f1 >= 0.95, (
        f'F1 Score {f1:.4f} is below threshold 0.95. '
        f'True Positives: {true_positives}, False Positives: {false_positives}, '
        f'False Negatives: {false_negatives}.'
    )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
