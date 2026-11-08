#!/bin/bash
set +e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import json
import os
import pytest

def test_final_billing_json_exists():
    assert os.path.isfile('/home/user/final_billing.json'), "The /home/user/final_billing.json file is missing."

def test_final_billing_json_content():
    with open('/home/user/final_billing.json', 'r') as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail("The /home/user/final_billing.json file does not contain valid JSON.")

    assert "total_revenue" in data, "Missing 'total_revenue' in JSON."
    assert "users" in data, "Missing 'users' in JSON."

    assert data["total_revenue"] == 13.5, f"Expected total_revenue to be 13.5, got {data['total_revenue']}."

    users = data["users"]
    assert "user1" in users, "Missing 'user1' in users dictionary."
    assert "user2" in users, "Missing 'user2' in users dictionary."

    assert users["user1"] == 9.5, f"Expected user1 cost to be 9.5, got {users['user1']}."
    assert users["user2"] == 4.0, f"Expected user2 cost to be 4.0, got {users['user2']}."

def test_billing_processor_fixes():
    assert os.path.isfile('/home/user/billing_processor.py'), "The billing_processor.py script is missing."
    with open('/home/user/billing_processor.py', 'r') as f:
        content = f.read()

    # Check for sorting
    assert "sort" in content or "sorted(" in content, "The script does not appear to sort the events chronologically."

    # Check for thread safety fix (unsafe concatenation removed)
    assert "all_events = all_events + local_events" not in content, "The unsafe list concatenation is still present in billing_processor.py."
TEST_EOF

cat << 'DYNAMIC_EOF' > /tmp/test_dynamic_billing.py
import datetime
import json
import math
import os
import runpy
import secrets
import shutil
import tempfile
import threading

SCRIPT = '/home/user/billing_processor.py'
LOGDIR = '/home/user/logs'
OUTPUT = '/home/user/final_billing.json'

assert os.path.isfile(SCRIPT), 'The billing_processor.py script is missing.'

backup_root = tempfile.mkdtemp(prefix='billing-verifier-')
backup_logs = os.path.join(backup_root, 'logs')
shutil.copytree(LOGDIR, backup_logs)
had_output = os.path.exists(OUTPUT)
backup_output = os.path.join(backup_root, 'final_billing.json')
if had_output:
    shutil.copy2(OUTPUT, backup_output)

try:
    shutil.rmtree(LOGDIR)
    os.makedirs(LOGDIR)
    if os.path.exists(OUTPUT):
        os.remove(OUTPUT)

    token = secrets.token_hex(6)
    main_user = 'main_' + token
    bad_user = 'bad_' + token
    base = datetime.datetime(2025, 1, 1, 0, 0, 0)
    records = []

    def line(ts, user, action, value=None):
        records.append((ts, user, action, value))
        suffix = '' if value is None else ' ' + str(value)
        return f"{ts:%Y-%m-%d %H:%M:%S} {user} {action}{suffix}\n"

    # The physical line order is deliberately opposite to timestamp order.
    with open(os.path.join(LOGDIR, '000_reverse.log'), 'w') as f:
        f.write(line(base + datetime.timedelta(seconds=2), main_user, 'UPLOAD', 173))
        f.write(line(base, main_user, 'LOGIN'))

    # A chronologically unauthorized transfer must retain the existing penalty.
    with open(os.path.join(LOGDIR, '001_unauthorized.log'), 'w') as f:
        f.write(line(base + datetime.timedelta(seconds=12), bad_user, 'LOGOUT'))
        f.write(line(base + datetime.timedelta(seconds=10), bad_user, 'DOWNLOAD', 7))
        f.write(line(base + datetime.timedelta(seconds=11), bad_user, 'LOGIN'))

    # Many independently read files exercise collection of events from threads.
    sequence = 100
    for file_no in range(40):
        path = os.path.join(LOGDIR, f'{100 + file_no:03d}_data.log')
        with open(path, 'w') as f:
            for _ in range(300):
                ts = base + datetime.timedelta(seconds=sequence)
                f.write(line(ts, main_user, 'DOWNLOAD', 1))
                sequence += 1

    with open(os.path.join(LOGDIR, '900_main_logout.log'), 'w') as f:
        f.write(line(base + datetime.timedelta(seconds=19000), main_user, 'LOGOUT'))

    # Randomized users and amounts prevent a fixed expected JSON from passing.
    for i in range(8):
        user = f'u{i}_{token}'
        amount = 101 + secrets.randbelow(400)
        download = 1 + secrets.randbelow(60)
        start = 20000 + i * 10
        path = os.path.join(LOGDIR, f'{950 + i:03d}_mixed.log')
        with open(path, 'w') as f:
            f.write(line(base + datetime.timedelta(seconds=start + 2), user, 'UPLOAD', amount))
            f.write(line(base + datetime.timedelta(seconds=start), user, 'LOGIN'))
            f.write(line(base + datetime.timedelta(seconds=start + 3), user, 'DOWNLOAD', download))
            f.write(line(base + datetime.timedelta(seconds=start + 4), user, 'LOGOUT'))

    expected_users = {}
    active = set()
    for ts, user, action, value in sorted(records, key=lambda item: item[0]):
        expected_users.setdefault(user, 0.0)
        if action == 'LOGIN':
            active.add(user)
            expected_users[user] += 1.50
        elif action == 'LOGOUT':
            active.discard(user)
        elif user not in active:
            expected_users[user] += 10.00
        elif action == 'UPLOAD':
            expected_users[user] += value * 0.05 if value <= 100 else 5.00 + (value - 100) * 0.02
        elif action == 'DOWNLOAD':
            expected_users[user] += value * 0.10
    expected_total = sum(expected_users.values())

    # Execute the submitted artifact and verify that it actually starts threads.
    real_thread = threading.Thread
    starts = [0]

    class TrackingThread(real_thread):
        def start(self):
            starts[0] += 1
            return super().start()

    threading.Thread = TrackingThread
    old_cwd = os.getcwd()
    try:
        os.chdir('/home/user')
        runpy.run_path(SCRIPT, run_name='__main__')
    finally:
        os.chdir(old_cwd)
        threading.Thread = real_thread

    assert starts[0] >= 2, 'The submitted script did not preserve parallel threaded file reading.'
    assert os.path.isfile(OUTPUT), 'Running billing_processor.py did not create final_billing.json.'
    with open(OUTPUT) as f:
        result = json.load(f)

    assert set(result) == {'total_revenue', 'users'}, 'The output must contain exactly total_revenue and users.'
    assert isinstance(result['users'], dict), 'The users value must be a dictionary.'
    assert set(result['users']) == set(expected_users), 'The generated user set is incorrect for the test logs.'
    for user, expected in expected_users.items():
        actual = result['users'][user]
        assert isinstance(actual, (int, float)) and not isinstance(actual, bool)
        assert math.isclose(actual, expected, rel_tol=0.0, abs_tol=1e-7), \
            f'Incorrect charge for {user}: expected {expected}, got {actual}'
    assert math.isclose(result['total_revenue'], expected_total, rel_tol=0.0, abs_tol=1e-7), \
        f"Incorrect total revenue: expected {expected_total}, got {result['total_revenue']}"
finally:
    if os.path.exists(LOGDIR):
        shutil.rmtree(LOGDIR)
    shutil.copytree(backup_logs, LOGDIR)
    if had_output:
        shutil.copy2(backup_output, OUTPUT)
    elif os.path.exists(OUTPUT):
        os.remove(OUTPUT)
    shutil.rmtree(backup_root)
DYNAMIC_EOF

(
    rm -f /home/user/final_billing.json &&
    cd /home/user && python3 /home/user/billing_processor.py &&
    python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1 &&
    python3 /tmp/test_dynamic_billing.py
)
status=$?

if [ "$status" -eq 0 ]; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
